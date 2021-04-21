pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../../interfaces/ICErc20.sol";

/**
 * @title Compound Batcher - batch multiple user's funds to supply to Compound,
          utilises permit functions so users can batch deposit to the protocol.
 * @author kjr217
 */

contract CompoundBatcherV2 is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;


    // track the deposit amount for a user for a specific deposit id
    mapping(address => mapping(uint256 => uint256)) public userDepositAmount;

    // amount available to deposit to Compound by batch
    mapping(uint256 => uint256) public batchTotals;

    //amount available in cTokens for a specific batch
    mapping(uint256 => uint256) public batchCTokenTotals;

    // address of the compound token associated with the underlying asset
    address public cToken;

    // address of the underlying asset
    address public token;

    // has the contract been initiated
    bool private isInitiated;

    // depositor fee
    uint256 public constant depositorFeeCoefficient = 5e15;

    // counter to track the current batch number
    Counters.Counter public batchIdTracker;

    event UserDeposited(address indexed user, uint256 amount, uint256 batchId);
    event FundsDepositedToCompound(uint256 amount, uint256 cTokenAmount, uint256 batchId);
    event CTokenWithdrawn(address indexed user, uint256 amount, uint256 batchId);
    event FundsWithdrawnBeforeDeposit(address indexed user, uint256 amount, uint256 batchId);

    /**
     * @notice initiate the contract, this is being used instead
               of a constructor to make the contract proxyable
     * @param _cToken the compound token address for this contract
     * @param _token the underlying asset token address of this contract,
              associated with _cToken
     */
    function init(
        address _cToken,
        address _token
    ) external
    {
        require(!isInitiated,
            "init: This contract has already been initiated");
        cToken = _cToken;
        token = _token;
        isInitiated = true;
    }

    /**
     * @notice return the current counter number
     * @return the batchId
     */
    function batchIdCounter() public view returns (uint256) {
        return batchIdTracker.current();
    }

    /**
     * @notice return the total underlying funds for a specific batchId
     * @return the amount of funds
     */
    function batchTotal(uint256 _batchId) public view returns (uint256) {
        return batchTotals[_batchId];
    }
    /**
     * @notice deposit function to place funds to be deposited
     * @param _amount amount of the token associated with the contract to transfer
     */
    function deposit(
        uint256 _amount
    ) public {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 batchId_ = batchIdTracker.current();
        batchTotals[batchId_] += _amount;
        userDepositAmount[msg.sender][batchId_] += _amount;

        emit UserDeposited(msg.sender, _amount, batchId_);
    }

    function permitAndDeposit(uint256 amount, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        IERC20Permit(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
        deposit(amount);
    }

    function permitEIP2612AndDeposit(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        IERC20Permit(token).permit(msg.sender, address(this), amount, expiry, v, r, s);
        deposit(amount);
    }

    function permitEIP2612AndDepositUnlimited(uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        IERC20Permit(token).permit(msg.sender, address(this), uint256(-1), expiry, v, r, s);
        deposit(amount);
    }

    /**
     * @notice function to allow anyone to deposit funds to Compound
     * @dev applies a fee, currently changed by the admin.
            It doesnt make sense for an actor to call this unless the
            deposit fee is greater than the cumulative gas cost,
            so it is unlikely that this can be exploited.
     */
    function depositToCompound() external nonReentrant {
        uint256 batchId_ = batchIdTracker.current();
        uint256 batchTotal_ = batchTotals[batchId_];
        require(batchTotal_ > 0, "depositToCompound: no funds to deposit");

        address cToken_ = cToken;
        uint256 cBalanceBefore = IERC20(cToken_).balanceOf(address(this));
        // Approve transfer on the ERC20 contract
        IERC20(token).approve(cToken_, batchTotal_);
        // Mint cTokens
        uint256 mintResult =
            ICErc20(cToken_).mint(batchTotal_);
        require(mintResult == 0, "depositToCompound: mintResult error");
        uint256 cBalanceAfter = IERC20(cToken_).balanceOf(address(this));
        // determine balance of cTokens received
        uint256 depositedCToken = cBalanceAfter.sub(cBalanceBefore);
        // apply fee
        uint256 depositorFee = (depositedCToken.mul(depositorFeeCoefficient)).div(1e18);
        depositedCToken = depositedCToken.sub(depositorFee);

        batchCTokenTotals[batchId_] = depositedCToken;
        batchIdTracker.increment();

        // transfer depositorFee to depositor
        IERC20(cToken_).safeTransfer(msg.sender, depositorFee);

        emit FundsDepositedToCompound(batchTotal_, depositedCToken, batchId_);
    }

    /**
     * @notice Function to allow a user to withdraw their cTokens for a specific batchId
     * @param _batchId the id of the deposit that the user wants to withdraw from
     */
    function userWithdrawCTokens(uint256 _batchId) external {
        require(_batchId < batchIdCounter(), "userWithdrawCToken: Batch id invalid");

        uint256 depositAmount = userDepositAmount[msg.sender][_batchId];
        uint256 batchCTokenAmount = batchCTokenTotals[_batchId];
        uint256 batchUnderlyingAmount = batchTotals[_batchId];
        require(depositAmount > 0, "userWithdrawCToken: No funds to withdraw for the given deposit id");

        uint256 cTokenAllocation = depositAmount
                    .mul(batchCTokenAmount)
                    .div(batchUnderlyingAmount);
        if (cTokenAllocation > batchCTokenAmount){
            cTokenAllocation = batchCTokenAmount;
        }

        batchCTokenTotals[_batchId] = batchCTokenAmount.sub(cTokenAllocation);
        batchTotals[_batchId] = batchUnderlyingAmount.sub(depositAmount);
        userDepositAmount[msg.sender][_batchId] = 0;

        IERC20(cToken).safeTransfer(msg.sender, cTokenAllocation);
        emit CTokenWithdrawn(msg.sender, cTokenAllocation, _batchId);
    }
}

interface IERC20Permit is IERC20 {

    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    //EIP2612 implementation
    function permit(
        address holder,
        address spender,
        uint256 amount,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address holder) external view returns(uint);
}
