// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract SimpleAMM {
    using SafeERC20 for IERC20;

    IERC20 public token0;
    IERC20 public token1;

    uint112 private reserve0;
    uint112 private reserve1;

    // A small constant fee structure: 0.3%, like Uniswap v2
    // For every 1000 tokens in, only 997 are effectively used for the swap calculation.
    uint256 private constant FEE_MULTIPLIER = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    constructor(IERC20 _token0, IERC20 _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    // Add liquidity by transferring tokens to this contract.
    // Equivalent to depositing liquidity: just call this function with desired amounts,
    // and the contract updates internal reserves.
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        _update();
    }

    // Swap tokens: if zeroForOne is true, user inputs token0 and receives token1.
    // Otherwise, user inputs token1 and receives token0.
    function swap(bool zeroForOne, uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");

        // Get current reserves
        (uint112 _reserve0, uint112 _reserve1) = getReserves();

        (IERC20 tokenIn, IERC20 tokenOut, uint112 reserveIn, uint112 reserveOut) =
            zeroForOne ? (token0, token1, _reserve0, _reserve1) : (token1, token0, _reserve1, _reserve0);

        // Transfer in the input tokens first
        // This ensures that by the time we do our math, the contract holds the input tokens.
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        // Apply fee
        uint256 amountInWithFee = amountIn * FEE_MULTIPLIER;
        // Uniswap v2 formula
        // amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee)
        amountOut = (amountInWithFee * reserveOut) / (uint256(reserveIn) * FEE_DENOMINATOR + amountInWithFee);

        require(amountOut > 0 && amountOut < reserveOut, "Insufficient liquidity for this swap");

        // Transfer out the output tokens
        tokenOut.safeTransfer(msg.sender, amountOut);

        // Update reserves after the swap
        _update();
    }

    // Recalculate reserves to match contract balances
    function _update() private {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Overflow");
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
    }
}
