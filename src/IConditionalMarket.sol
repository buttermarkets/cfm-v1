// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IConditionalMarket {
    function resolve() external;

    function isResolved() external view returns (bool);
}
