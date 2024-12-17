// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

abstract contract ConditionalMarket {
    function resolve() external virtual;

    function isResolved() external view virtual returns (bool);
}
