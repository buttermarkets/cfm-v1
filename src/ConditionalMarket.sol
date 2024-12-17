// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract ConditionalMarket {
    function resolve() external virtual;

    function isResolved() external view virtual returns (bool);
}
