// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IVammClearingHouse} from "../interfaces/IVammClearingHouse.sol";
import {ITraderMonitor} from "../interfaces/ITraderMonitor.sol";

contract MockClearingHouse is IVammClearingHouse {
    ITraderMonitor public traderMonitor;

    constructor(address _traderMonitor) {
        traderMonitor = ITraderMonitor(_traderMonitor);
    }

    function setTraderMonitor(address _traderMonitor) external {
        traderMonitor = ITraderMonitor(_traderMonitor);
    }

    function updateTrader(
        address trader,
        uint256 liquidationPrice,
        bool isLiquidated
    ) external {
        traderMonitor.updateTrader(trader, liquidationPrice, isLiquidated);
    }

    function liquidate(
        address
    ) external override returns (bool, uint256, uint256) {
        // not doing anything
        return (true, 0, 0);
    }
}
