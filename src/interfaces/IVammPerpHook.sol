// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IVammPerpHook {
    function liquidate(address user) external;

    function liquidatePosition(address user, bytes32 marketId) external;
}
