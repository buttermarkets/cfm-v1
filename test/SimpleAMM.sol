// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract SimpleAMM {
    using SafeERC20 for IERC20;

    IERC20 public token0;
    IERC20 public token1;
    uint256 public reserve0;
    uint256 public reserve1;
    uint256 private constant PRECISION = 1e18;

    constructor(IERC20 _token0, IERC20 _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
        reserve0 += amount0;
        reserve1 += amount1;
    }

    function swap(bool zeroForOne, uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");

        (IERC20 tokenIn, IERC20 tokenOut, uint256 reserveIn, uint256 reserveOut) =
            zeroForOne ? (token0, token1, reserve0, reserve1) : (token1, token0, reserve1, reserve0);

        // Simple x * y = k formula with 0.3% fee
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);

        // Update reserves
        if (zeroForOne) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }

        // Transfer tokens
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenOut.safeTransfer(msg.sender, amountOut);
    }
}
