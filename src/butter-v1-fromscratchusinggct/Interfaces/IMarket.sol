// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IMarket {
    function resolve() external;
    function getResolved() external view returns (bool);
}
