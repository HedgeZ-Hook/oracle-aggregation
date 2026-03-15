// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {BlockContext} from "../libraries/BlockContext.sol";

contract TickCumulativeTwap is BlockContext {
    struct Observation {
        int24 tick;
        int256 tickCumulative;
        uint256 timestamp;
    }

    uint16 public currentObservationIndex;
    uint16 internal constant MAX_OBSERVATION = 1800;
    Observation[MAX_OBSERVATION] public observations;

    function _updateTick(
        int24 tick,
        uint256 lastUpdatedTimestamp
    ) internal returns (bool) {
        if (currentObservationIndex == 0 && observations[0].timestamp == 0) {
            observations[0] = Observation({
                tick: tick,
                tickCumulative: 0,
                timestamp: lastUpdatedTimestamp
            });
            return true;
        }

        Observation memory lastObservation = observations[
            currentObservationIndex
        ];
        require(lastUpdatedTimestamp >= lastObservation.timestamp, "TCT_IT");

        if (lastUpdatedTimestamp == lastObservation.timestamp) {
            require(tick == lastObservation.tick, "TCT_ITWU");
        }

        if (tick == lastObservation.tick) {
            return false;
        }

        currentObservationIndex =
            (currentObservationIndex + 1) %
            MAX_OBSERVATION;

        uint256 timestampDiff = lastUpdatedTimestamp -
            lastObservation.timestamp;
        observations[currentObservationIndex] = Observation({
            tickCumulative: lastObservation.tickCumulative +
                (int256(lastObservation.tick) * int256(timestampDiff)),
            timestamp: lastUpdatedTimestamp,
            tick: tick
        });
        return true;
    }

    function _calculateAverageTick(
        uint256 interval,
        int24 tick,
        uint256 latestUpdatedTimestamp
    ) internal view returns (int24 averageTick, bool hasTwap) {
        if (
            (currentObservationIndex == 0 && observations[0].timestamp == 0) ||
            interval == 0
        ) {
            return (0, false);
        }

        Observation memory latestObservation = observations[
            currentObservationIndex
        ];

        if (latestObservation.timestamp == latestUpdatedTimestamp) {
            require(tick == latestObservation.tick, "TCT_ITWCT");
        }

        uint256 currentTimestamp = _blockTimestamp();
        if (currentTimestamp < interval) {
            return (0, false);
        }
        uint256 targetTimestamp = currentTimestamp - interval;
        int256 currentTickCumulative = latestObservation.tickCumulative +
            (int256(latestObservation.tick) *
                int256(latestUpdatedTimestamp - latestObservation.timestamp)) +
            (int256(tick) * int256(currentTimestamp - latestUpdatedTimestamp));

        (
            Observation memory beforeOrAt,
            Observation memory atOrAfter
        ) = _getSurroundingObservations(targetTimestamp);
        int256 targetTickCumulative;

        if (targetTimestamp == beforeOrAt.timestamp) {
            targetTickCumulative = beforeOrAt.tickCumulative;
        } else if (atOrAfter.timestamp == targetTimestamp) {
            targetTickCumulative = atOrAfter.tickCumulative;
        } else if (beforeOrAt.timestamp == atOrAfter.timestamp) {
            return (0, false);
        } else if (atOrAfter.timestamp == 0) {
            targetTickCumulative =
                beforeOrAt.tickCumulative +
                (int256(beforeOrAt.tick) *
                    int256(targetTimestamp - beforeOrAt.timestamp));
        } else {
            uint256 targetTimeDelta = targetTimestamp - beforeOrAt.timestamp;
            uint256 observationTimeDelta = atOrAfter.timestamp -
                beforeOrAt.timestamp;

            targetTickCumulative =
                beforeOrAt.tickCumulative +
                ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) *
                    int256(targetTimeDelta)) /
                int256(observationTimeDelta);
        }

        int256 tickDelta = currentTickCumulative - targetTickCumulative;
        int256 divisor = int256(interval);
        int256 averageTick256 = tickDelta / divisor;

        if (tickDelta < 0 && (tickDelta % divisor) != 0) {
            averageTick256--;
        }

        averageTick = int24(averageTick256);
        hasTwap = true;
    }

    function _calculatePriceTwap(
        uint256 interval,
        int24 tick,
        uint256 latestUpdatedTimestamp,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) internal view returns (uint256 priceE18, bool hasTwap) {
        (int24 averageTick, bool ready) = _calculateAverageTick(
            interval,
            tick,
            latestUpdatedTimestamp
        );
        if (!ready) {
            return (0, false);
        }

        return (_priceAtTick(averageTick, baseDecimals, quoteDecimals), true);
    }

    function _priceAtTick(
        int24 tick,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) internal pure returns (uint256) {
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        uint256 ratioX128 = FullMath.mulDiv(
            uint256(sqrtPriceX96),
            uint256(sqrtPriceX96),
            uint256(1) << 64
        );
        return
            FullMath.mulDiv(
                ratioX128,
                (10 ** baseDecimals) * 1e18,
                (uint256(1) << 128) * (10 ** quoteDecimals)
            );
    }

    function _inverseTick(int24 tick) internal pure returns (int24) {
        return -tick;
    }

    function _getSurroundingObservations(
        uint256 targetTimestamp
    )
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        beforeOrAt = observations[currentObservationIndex];

        if (
            observations[currentObservationIndex].timestamp <= targetTimestamp
        ) {
            return (beforeOrAt, atOrAfter);
        }

        beforeOrAt = observations[
            (currentObservationIndex + 1) % MAX_OBSERVATION
        ];
        if (beforeOrAt.timestamp == 0) {
            beforeOrAt = observations[0];
        }

        if (beforeOrAt.timestamp > targetTimestamp) {
            return (beforeOrAt, beforeOrAt);
        }

        return _binarySearch(targetTimestamp);
    }

    function _binarySearch(
        uint256 targetTimestamp
    )
        private
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint256 l = (currentObservationIndex + 1) % MAX_OBSERVATION;
        uint256 r = l + MAX_OBSERVATION - 1;
        uint256 i;

        while (true) {
            i = (l + r) / 2;
            beforeOrAt = observations[i % MAX_OBSERVATION];

            if (beforeOrAt.timestamp == 0) {
                l = i + 1;
                continue;
            }

            atOrAfter = observations[(i + 1) % MAX_OBSERVATION];

            bool targetAtOrAfter = beforeOrAt.timestamp <= targetTimestamp;
            if (targetAtOrAfter && targetTimestamp <= atOrAfter.timestamp) {
                break;
            }

            if (!targetAtOrAfter) {
                r = i - 1;
            } else {
                l = i + 1;
            }
        }
    }
}
