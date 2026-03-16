// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractCallback} from "@reactive/abstract-base/AbstractCallback.sol";
import {AbstractPausableReactive} from "@reactive/abstract-base/AbstractPausableReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";

contract LiquidationMonitorReactive is
    IReactive,
    AbstractPausableReactive,
    AbstractCallback
{
    uint64 public constant DEFAULT_CALLBACK_GAS_LIMIT = 1_000_000;
    bytes32 public constant TRADER_LIQUIDATION_UPDATE_TOPIC =
        keccak256("TraderLiquidationUpdate(address,uint256)");
    bytes32 public constant TRADER_LIQUIDATED_TOPIC =
        keccak256("TraderLiquidated(address)");

    uint256 public immutable traderSourceChainId;
    address public immutable traderSourceContract;
    address public immutable priceAggregationReactive;
    address public immutable liquidationExecutor;
    uint256 public immutable liquidationExecutorChainId;
    uint64 public immutable liquidationExecutorGasLimit;

    mapping(address => uint256) public liquidationPriceE18;
    mapping(address => uint256) public traderIndexPlusOne;
    address[] public traders;

    event TraderTracked(address indexed trader, uint256 liquidationPriceE18);
    event TraderRemoved(address indexed trader);
    event LiquidationRequested(
        address indexed trader,
        uint256 liquidationPriceE18,
        uint256 currentPriceE18
    );

    constructor(
        uint256 traderSourceChainId_,
        address traderSourceContract_,
        address priceAggregationReactive_,
        address liquidationExecutor_,
        uint256 liquidationExecutorChainId_,
        uint64 liquidationExecutorGasLimit_
    ) payable AbstractCallback(address(SERVICE_ADDR)) {
        require(traderSourceContract_ != address(0), "zero source");
        require(priceAggregationReactive_ != address(0), "zero aggregator");
        require(liquidationExecutor_ != address(0), "zero executor");

        traderSourceChainId = traderSourceChainId_;
        traderSourceContract = traderSourceContract_;
        priceAggregationReactive = priceAggregationReactive_;
        liquidationExecutor = liquidationExecutor_;
        liquidationExecutorChainId = liquidationExecutorChainId_;
        liquidationExecutorGasLimit = liquidationExecutorGasLimit_ == 0
            ? DEFAULT_CALLBACK_GAS_LIMIT
            : liquidationExecutorGasLimit_;

        if (!vm) {
            service.subscribe(
                traderSourceChainId,
                traderSourceContract,
                uint256(TRADER_LIQUIDATION_UPDATE_TOPIC),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            service.subscribe(
                liquidationExecutorChainId,
                liquidationExecutor,
                uint256(TRADER_LIQUIDATED_TOPIC),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function traderCount() external view returns (uint256) {
        return traders.length;
    }

    function onAggregatedPrice(
        address sender,
        uint256 currentPriceE18,
        uint256 activePools
    ) external authorizedSenderOnly {
        require(sender == priceAggregationReactive, "bad aggregator");
        if (activePools == 0 || currentPriceE18 == 0) {
            return;
        }

        uint256 traderCount_ = traders.length;
        for (uint256 i = 0; i < traderCount_; ++i) {
            address trader = traders[i];
            uint256 liquidationPrice = liquidationPriceE18[trader];
            if (liquidationPrice == 0 || liquidationPrice <= currentPriceE18) {
                continue;
            }

            bytes memory payload = abi.encodeWithSignature(
                "liquidateTrader(address)",
                trader
            );
            emit Callback(
                liquidationExecutorChainId,
                liquidationExecutor,
                liquidationExecutorGasLimit,
                payload
            );
            emit LiquidationRequested(trader, liquidationPrice, currentPriceE18);
        }
    }

    function react(LogRecord calldata log) external vmOnly {
        if (
            log.chain_id == traderSourceChainId &&
            log._contract == traderSourceContract &&
            log.topic_0 == uint256(TRADER_LIQUIDATION_UPDATE_TOPIC)
        ) {
            _handleLiquidationUpdate(log.data);
            return;
        }

        if (
            log.chain_id == liquidationExecutorChainId &&
            log._contract == liquidationExecutor &&
            log.topic_0 == uint256(TRADER_LIQUIDATED_TOPIC)
        ) {
            _handleLiquidated(address(uint160(log.topic_1)));
            return;
        }

        revert("unsupported log");
    }

    function getPausableSubscriptions()
        internal
        view
        override
        returns (Subscription[] memory subscriptions)
    {
        subscriptions = new Subscription[](2);

        subscriptions[0] = Subscription({
            chain_id: traderSourceChainId,
            _contract: traderSourceContract,
            topic_0: uint256(TRADER_LIQUIDATION_UPDATE_TOPIC),
            topic_1: REACTIVE_IGNORE,
            topic_2: REACTIVE_IGNORE,
            topic_3: REACTIVE_IGNORE
        });

        subscriptions[1] = Subscription({
            chain_id: liquidationExecutorChainId,
            _contract: liquidationExecutor,
            topic_0: uint256(TRADER_LIQUIDATED_TOPIC),
            topic_1: REACTIVE_IGNORE,
            topic_2: REACTIVE_IGNORE,
            topic_3: REACTIVE_IGNORE
        });
    }

    function _handleLiquidationUpdate(bytes calldata data) internal {
        (address trader, uint256 liquidationPrice) = abi.decode(
            data,
            (address, uint256)
        );

        if (liquidationPrice == 0) {
            _removeTrader(trader);
            return;
        }

        liquidationPriceE18[trader] = liquidationPrice;
        if (traderIndexPlusOne[trader] == 0) {
            traders.push(trader);
            traderIndexPlusOne[trader] = traders.length;
        }

        emit TraderTracked(trader, liquidationPrice);
    }

    function _handleLiquidated(address trader) internal {
        _removeTrader(trader);
    }

    function _removeTrader(address trader) internal {
        uint256 indexPlusOne = traderIndexPlusOne[trader];
        delete liquidationPriceE18[trader];

        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = traders.length - 1;
        if (index != lastIndex) {
            address movedTrader = traders[lastIndex];
            traders[index] = movedTrader;
            traderIndexPlusOne[movedTrader] = index + 1;
        }

        traders.pop();
        delete traderIndexPlusOne[trader];

        emit TraderRemoved(trader);
    }
}
