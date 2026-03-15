// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {AbstractReactive} from "@reactive/abstract-base/AbstractReactive.sol";
import {ISystemContract} from "@reactive/interfaces/ISystemContract.sol";

contract BasicDemoReactiveContract is IReactive, AbstractReactive {
    uint256 public originChainId;
    uint256 public destinationChainId;
    uint64 private constant GAS_LIMIT = 1000000;

    address private callback;

    constructor(
        address _service,
        uint256 _originChainId,
        uint256 _destinationChainId,
        address _contract,
        uint256 _topic_0,
        address _callback
    ) payable {
        service = ISystemContract(payable(_service));

        originChainId = _originChainId;
        destinationChainId = _destinationChainId;
        callback = _callback;

        if (!vm) {
            service.subscribe(
                originChainId,
                _contract,
                _topic_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {}
}
