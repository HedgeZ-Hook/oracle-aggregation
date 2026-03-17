// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ITraderMonitor {
    function updateTrader(
        address trader,
        uint256 liquidationPrice,
        bool isLiquidated
    ) external;
}
