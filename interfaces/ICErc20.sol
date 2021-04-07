pragma solidity 0.7.4;

/**
 * @title Interface for Compound ERC20
 */
interface ICErc20 {
    function mint(uint256) external returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function supplyRatePerBlock() external returns (uint256);
    function redeem(uint) external returns (uint);
    function redeemUnderlying(uint) external returns (uint);
    function balanceOf(address) external view returns (uint256);
    function balanceOfUnderlying(address) external view returns (uint256);

}