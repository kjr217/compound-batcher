pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/EnumerableSet.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../interfaces/ICErc20.sol";

/**
 * @title Compound Batcher - batch multiple user's funds to supply to Compound,
          this version of the contract is more decentralised, as the
          depositToCompound function is open
 * @author kjr217
 */

contract CompoundBatcher is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using Counters for Counters.Counter;

    struct depositDetails {
        uint256 cTokenAmount;
        uint256 tokenAmount;
    }

    // track the deposit ids that a user has been involved in
    mapping(address => EnumerableSet.UintSet) private userDepositIds;

    // track the deposit amount for a user for a specific deposit id
    mapping(address => mapping(uint256 => uint256)) public userDepositAmount;

    // storage for admins
    mapping(address => bool) public isAdmin;

    // storage for the regular deposits
    mapping(uint256 => depositDetails) public depositInfo;

    // amount available to deposit to Compound
    uint256 public toDeposit;

    // address of the compound token associated with the underlying asset
    address public cToken;

    // address of the underlying asset
    address public token;

    // has the contract been initiated
    bool private isInitiated;

    // depositor fee
    uint256 public constant depositorFeeCoefficient = 5e15;

    // counter to track the current deposit number
    Counters.Counter public depositIdTracker;

    event UserDeposited(address indexed user, uint256 amount, uint256 depositId);
    event AdminAssigned(address indexed admin);
    event AdminRemoved(address indexed admin);
    event FundsDepositedToCompound(uint256 amount, uint256 depositId);
    event CTokenWithdrawn(address indexed user, uint256 amount, uint256 depositId);
    event FundsWithdrawnBeforeDeposit(address indexed user, uint256 amount, uint256 depositId);

    /**
     * @notice modifier to check that configured admin is making the call
     */
    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "Caller must be an admin");
        _;
    }

    /**
     * @notice initiate the contract, this is being used instead
               of a constructor to make the contract proxyable
     * @param _cToken the compound token address for this contract
     * @param _token the underlying asset token address of this contract,
              associated with _cToken
     * @param _admin the original admin for this contract
     */
    function init(
        address _cToken,
        address _token,
        address _admin
    ) external
    {
        require(!isInitiated,
            "init: This contract has already been initiated");
        cToken = _cToken;
        token = _token;
        isAdmin[_admin] = true;
        isInitiated = true;
    }

    /**
     * @notice return the current counter number
     * @return the depositId
     */
    function depositIdCounter() public view returns (uint256) {
        return depositIdTracker.current();
    }

    /**
     * @notice assign an admin to the contract to call the compound deposit function
     * @param _newAdmin the address of the admin to be assigned
     */
    function assignAdmin(address _newAdmin) external onlyAdmin {
        isAdmin[_newAdmin] = true;
        emit AdminAssigned(_newAdmin);
    }

    /**
     * @notice remove an admin to the contract
     * @param _admin the address of the admin to be removed
     */
    function removeAdmin(address _admin) external onlyAdmin {
        isAdmin[_admin] = false;
        emit AdminRemoved(_admin);
    }



    /**
     * @notice deposit function to place funds to be deposited
     * @param _amount amount of the token associated with the contract to transfer
     */
    function userDeposit(
        uint256 _amount
    ) external {

        address token_ = token;
        toDeposit += _amount;
        uint256 depositId_ = depositIdTracker.current();
        userDepositIds[msg.sender].add(depositId_);
        userDepositAmount[msg.sender][depositId_] += _amount;
        IERC20(token_).safeTransferFrom(msg.sender, address(this), _amount);

        emit UserDeposited(msg.sender, _amount, depositId_);
    }

    /**
     * @notice withdraw funds before they are deposited
     */
    function userWithdrawBeforeDeposit() external {

        uint256 depositId_ = depositIdTracker.current();
        uint256 depositAmount = userDepositAmount[msg.sender][depositId_];
        require(depositAmount > 0,
            "userWithdrawBeforeDeposit: No funds to withdraw");
        userDepositAmount[msg.sender][depositId_] = 0;
        userDepositIds[msg.sender].remove(depositId_);
        toDeposit.sub(depositAmount);

        IERC20(token).safeTransfer(msg.sender, depositAmount);

        emit FundsWithdrawnBeforeDeposit(msg.sender, depositAmount, depositId_);
    }

    /**
     * @notice function to allow anyone to deposit funds to Compound
     * @dev applies a fee, currently changed by the admin.
            It doesnt make sense for an actor to call this unless the
            deposit fee is greater than the cumulative gas cost,
            so it is unlikely that this can be exploited.
     */
    function depositToCompound() external nonReentrant {

        uint256 toDeposit_ = toDeposit;
        require(toDeposit_ > 0, "depositToCompound: no funds to deposit");
        toDeposit = 0;
        address cToken_ = cToken;
        uint256 cBalanceBefore = IERC20(cToken_).balanceOf(address(this));

        // Approve transfer on the ERC20 contract
        IERC20(token).approve(cToken_, toDeposit_);
        // Mint cTokens
        uint256 mintResult =
            ICErc20(cToken_).mint(toDeposit_);
        require(mintResult == 0, "depositToCompound: mintResult error");

        uint256 cBalanceAfter = IERC20(cToken_).balanceOf(address(this));
        // determine balance of cTokens received
        uint256 depositedCToken = cBalanceAfter.sub(cBalanceBefore);
        // apply fee
        uint256 depositorFee = (depositedCToken.mul(depositorFeeCoefficient)).div(1e18);
        uint256 realCTokenAmount = depositedCToken.sub(depositorFee);
        uint256 depositId_ = depositIdTracker.current();
        depositInfo[depositId_] =
            depositDetails({
                cTokenAmount: realCTokenAmount,
                tokenAmount: toDeposit_
                });
        depositIdTracker.increment();

        // transfer depositorFee to depositor
        IERC20(cToken_).safeTransfer(msg.sender, depositorFee);

        emit FundsDepositedToCompound(toDeposit_, depositId_);
    }

    /**
     * @notice Function to allow a user to withdraw their cTokens
     * @dev In case that this function hits the block gas limit,
            an individual depositId redemption function exists.
     */
    function userWithdrawAllCTokens() external {

        uint256 setLength = userDepositIds[msg.sender].length();
        require(setLength > 0, "userWithdrawAllCTokens: msg.sender is not eligible for any allocation");

        uint256 cTokenAllocation = 0;
        // go through the enumerable set for the depositIds to determine what cTokens to withdraw.
        for(uint256 i=0; i < setLength; i++){
            uint256 depositId = userDepositIds[msg.sender].at(i);
            uint256 withdrawAmount = userDepositAmount[msg.sender][depositId];
            depositDetails memory originalDeposit = depositInfo[depositId];
            cTokenAllocation += (originalDeposit.cTokenAmount
                    .mul(withdrawAmount))
                    .div(originalDeposit.tokenAmount);
            emit CTokenWithdrawn(msg.sender, cTokenAllocation, depositId);
        }
        // remove the depositIds from the user
        for(uint256 i=0; i < setLength; i++){
            uint256 depositId = userDepositIds[msg.sender].at(0);
            userDepositIds[msg.sender].remove(depositId);
        }
        IERC20(cToken).safeTransferFrom(address(this), msg.sender, cTokenAllocation);
    }

    /**
     * @notice Function to allow a user to withdraw their cTokens for a specific depositId
     * @param _depositId the id of the deposit that the user wants to withdraw from
     */
    function userWithdrawCToken(uint256 _depositId) external {
        uint256 withdrawAmount = userDepositAmount[msg.sender][_depositId];
        require(withdrawAmount > 0, "userWithdrawCToken: No funds to withdraw for the given deposit id");
        depositDetails memory originalDeposit = depositInfo[_depositId];
        uint256 cTokenAllocation = originalDeposit.cTokenAmount
                    .mul(withdrawAmount)
                    .div(originalDeposit.tokenAmount);
        userDepositIds[msg.sender].remove(_depositId);
        IERC20(cToken).safeTransfer(msg.sender, cTokenAllocation);
        emit CTokenWithdrawn(msg.sender, cTokenAllocation, _depositId);
    }
}
