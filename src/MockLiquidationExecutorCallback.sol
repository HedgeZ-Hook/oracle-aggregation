// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractCallback} from "@reactive/abstract-base/AbstractCallback.sol";

contract MockLiquidationExecutorCallback is AbstractCallback {
    event TraderLiquidated(address indexed trader);

    constructor(
        address callbackSender_
    ) payable AbstractCallback(callbackSender_) {}

    function liquidateTrader(address trader) external authorizedSenderOnly {
        emit TraderLiquidated(trader);
    }
}
