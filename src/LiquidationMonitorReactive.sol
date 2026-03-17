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
    uint64 public constant DEFAULT_CALLBACK_GAS_LIMIT = 5_000_000;
    bytes32 public constant LIQUIDATION_PRICE_CHANGE_TOPIC =
        keccak256("LiquidationPriceChange(address,uint256,bool)");

    uint256 public immutable sourceChainId;
    // Emits LiquidationPriceChange(address,uint256,bool) updates for tracked traders.
    address public immutable sourceContract;
    // PriceAggregationReactive contract that handle for onAggregatedPrice(...).
    address public immutable priceAggregationContract;
    uint256 public immutable destinationChainId;
    address public immutable destinationContract;
    uint64 public immutable destinationGasLimit;

    mapping(address => uint256) public liquidationPriceE18;
    mapping(address => uint256) public tradersIdx; // index in array, remember it is index + 1
    address[] public traders;

    event TraderTracked(address indexed trader, uint256 liquidationPriceE18);
    event LiquidationSuccess(
        address indexed trader,
        uint256 liquidationPriceE18
    );
    event LiquidationRequested(
        address indexed trader,
        uint256 liquidationPriceE18,
        uint256 currentPriceE18
    );

    constructor(
        uint256 _sourceChainId,
        address _sourceContract,
        address _priceAggregationContract,
        uint256 _destinationChainId,
        address _destinationContract,
        uint64 _destinationGasLimit
    ) payable AbstractCallback(address(SERVICE_ADDR)) {
        require(_sourceContract != address(0), "zero source");
        require(_priceAggregationContract != address(0), "zero aggregator");
        require(_destinationContract != address(0), "zero destination");

        sourceChainId = _sourceChainId;
        sourceContract = _sourceContract;
        priceAggregationContract = _priceAggregationContract;
        destinationChainId = _destinationChainId;
        destinationContract = _destinationContract;
        destinationGasLimit = _destinationGasLimit == 0
            ? DEFAULT_CALLBACK_GAS_LIMIT
            : _destinationGasLimit;

        if (!vm) {
            service.subscribe(
                sourceChainId,
                sourceContract,
                uint256(LIQUIDATION_PRICE_CHANGE_TOPIC),
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
        require(
            sender == priceAggregationContract,
            "ERR: bad price aggregation contract"
        );
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
                "liquidate(address)",
                trader
            );
            emit Callback(
                destinationChainId,
                destinationContract,
                destinationGasLimit,
                payload
            );
            emit LiquidationRequested(
                trader,
                liquidationPrice,
                currentPriceE18
            );
        }

        bytes memory oraclePayload = abi.encodeWithSignature(
            "updateOraclePrice(uint256)",
            currentPriceE18
        );
        emit Callback(
            destinationChainId,
            destinationContract,
            destinationGasLimit,
            oraclePayload
        );
    }

    function react(LogRecord calldata log) external vmOnly {
        if (
            log.chain_id == sourceChainId &&
            log._contract == sourceContract &&
            log.topic_0 == uint256(LIQUIDATION_PRICE_CHANGE_TOPIC)
        ) {
            _handleLiquidationPriceChange(log.data);
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
        subscriptions = new Subscription[](1);

        subscriptions[0] = Subscription({
            chain_id: sourceChainId,
            _contract: sourceContract,
            topic_0: uint256(LIQUIDATION_PRICE_CHANGE_TOPIC),
            topic_1: REACTIVE_IGNORE,
            topic_2: REACTIVE_IGNORE,
            topic_3: REACTIVE_IGNORE
        });
    }

    function _handleLiquidationPriceChange(bytes calldata data) internal {
        (address trader, uint256 liquidationPrice, bool isLiquidated) = abi
            .decode(data, (address, uint256, bool));

        // user can't be liquidated due to position size in usd < their collateral
        if (liquidationPrice == 0 && isLiquidated) {
            _removeTrader(trader);
            return;
        }

        liquidationPriceE18[trader] = liquidationPrice;
        if (tradersIdx[trader] == 0) {
            traders.push(trader);
            tradersIdx[trader] = traders.length;
        }

        emit TraderTracked(trader, liquidationPrice);
    }

    function _removeTrader(address trader) internal {
        uint256 traderIdx = tradersIdx[trader];
        uint256 liquidationPrice = liquidationPriceE18[trader];
        delete liquidationPriceE18[trader];

        // meant unset
        if (traderIdx == 0) {
            return;
        }

        // for simplicity, we remove by update last trader to the position of removed trader
        // O(1)
        uint256 index = traderIdx - 1; // real index
        uint256 lastIndex = traders.length - 1;
        if (index != lastIndex) {
            address movedTrader = traders[lastIndex];
            traders[index] = movedTrader;
            tradersIdx[movedTrader] = index + 1;
        }
        traders.pop();
        delete tradersIdx[trader];

        emit LiquidationSuccess(trader, liquidationPrice);
    }
}
