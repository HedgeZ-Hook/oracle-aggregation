// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

library TickCumulativeOracleLib {
    uint16 internal constant MAX_OBSERVATION = 65535;

    struct Observation {
        int24 tick;
        int256 tickCumulative;
        uint256 timestamp;
    }

    struct State {
        uint16 currentObservationIndex;
        Observation[MAX_OBSERVATION] observations;
    }

    struct Cursor {
        uint16 beforeOrAtIndex;
        uint256 targetTimestamp;
        bool initialized;
    }

    function update(
        State storage self,
        int24 tick,
        uint256 lastUpdatedTimestamp
    ) internal returns (bool) {
        if (
            self.currentObservationIndex == 0 &&
            self.observations[0].timestamp == 0
        ) {
            self.observations[0] = Observation({
                tick: tick,
                tickCumulative: 0,
                timestamp: lastUpdatedTimestamp
            });
            return true;
        }

        Observation memory lastObservation = self.observations[
            self.currentObservationIndex
        ];
        require(lastUpdatedTimestamp >= lastObservation.timestamp, "TCT_IT");

        if (lastUpdatedTimestamp == lastObservation.timestamp) {
            if (tick == lastObservation.tick) {
                return false;
            }

            // Reactive timestamps are second-granularity, so multiple swaps from
            // a busy pool can collapse into the same observed second. In that
            // case we keep the cumulative value unchanged (dt = 0) and simply
            // retain the latest tick seen for the current timestamp.
            self.observations[self.currentObservationIndex].tick = tick;
            return true;
        }

        if (tick == lastObservation.tick) {
            return false;
        }

        self.currentObservationIndex =
            (self.currentObservationIndex + 1) %
            MAX_OBSERVATION;

        uint256 timestampDiff = lastUpdatedTimestamp -
            lastObservation.timestamp;
        self.observations[self.currentObservationIndex] = Observation({
            tick: tick,
            tickCumulative: lastObservation.tickCumulative +
                (int256(lastObservation.tick) * int256(timestampDiff)),
            timestamp: lastUpdatedTimestamp
        });
        return true;
    }

    function calculateAverageTick(
        State storage self,
        uint256 interval,
        int24 tick,
        uint256 latestUpdatedTimestamp,
        uint256 currentTimestamp
    ) internal view returns (int24 averageTick, bool hasTwap) {
        if (
            (self.currentObservationIndex == 0 &&
                self.observations[0].timestamp == 0) || interval == 0
        ) {
            return (0, false);
        }

        Observation memory latestObservation = self.observations[
            self.currentObservationIndex
        ];

        if (latestObservation.timestamp == latestUpdatedTimestamp) {
            require(tick == latestObservation.tick, "TCT_ITWCT");
        }

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
        ) = getSurroundingObservations(self, targetTimestamp);

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

    function calculateAverageTickWithCursor(
        State storage self,
        Cursor storage cursor,
        uint256 interval,
        int24 tick,
        uint256 latestUpdatedTimestamp,
        uint256 currentTimestamp
    ) internal returns (int24 averageTick, bool hasTwap) {
        if (
            (self.currentObservationIndex == 0 &&
                self.observations[0].timestamp == 0) || interval == 0
        ) {
            return (0, false);
        }

        Observation memory latestObservation = self.observations[
            self.currentObservationIndex
        ];

        if (latestObservation.timestamp == latestUpdatedTimestamp) {
            require(tick == latestObservation.tick, "TCT_ITWCT");
        }

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
        ) = getSurroundingObservationsWithCursor(self, cursor, targetTimestamp);

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

    function getSurroundingObservations(
        State storage self,
        uint256 targetTimestamp
    )
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        beforeOrAt = self.observations[self.currentObservationIndex];

        if (beforeOrAt.timestamp <= targetTimestamp) {
            return (beforeOrAt, atOrAfter);
        }

        beforeOrAt = self.observations[
            (self.currentObservationIndex + 1) % MAX_OBSERVATION
        ];
        if (beforeOrAt.timestamp == 0) {
            beforeOrAt = self.observations[0];
        }

        if (beforeOrAt.timestamp > targetTimestamp) {
            return (beforeOrAt, beforeOrAt);
        }

        (, beforeOrAt, atOrAfter) = binarySearchAll(self, targetTimestamp);
    }

    function getSurroundingObservationsWithCursor(
        State storage self,
        Cursor storage cursor,
        uint256 targetTimestamp
    )
        internal
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        beforeOrAt = self.observations[self.currentObservationIndex];

        if (beforeOrAt.timestamp <= targetTimestamp) {
            cursor.beforeOrAtIndex = self.currentObservationIndex;
            cursor.targetTimestamp = targetTimestamp;
            cursor.initialized = true;
            return (beforeOrAt, atOrAfter);
        }

        uint16 oldestIndex = uint16(
            (self.currentObservationIndex + 1) % MAX_OBSERVATION
        );
        beforeOrAt = self.observations[oldestIndex];
        if (beforeOrAt.timestamp == 0) {
            oldestIndex = 0;
            beforeOrAt = self.observations[0];
        }

        if (beforeOrAt.timestamp > targetTimestamp) {
            cursor.beforeOrAtIndex = oldestIndex;
            cursor.targetTimestamp = targetTimestamp;
            cursor.initialized = true;
            return (beforeOrAt, beforeOrAt);
        }

        if (cursor.initialized && cursor.targetTimestamp <= targetTimestamp) {
            uint16 narrowedBeforeIndex;
            (
                narrowedBeforeIndex,
                beforeOrAt,
                atOrAfter
            ) = binarySearchLimitedRange(
                self,
                targetTimestamp,
                cursor.beforeOrAtIndex,
                self.currentObservationIndex
            );
            cursor.beforeOrAtIndex = narrowedBeforeIndex;
            cursor.targetTimestamp = targetTimestamp;
            return (beforeOrAt, atOrAfter);
        }

        uint16 beforeIndex;
        (beforeIndex, beforeOrAt, atOrAfter) = binarySearchAll(
            self,
            targetTimestamp
        );
        cursor.beforeOrAtIndex = beforeIndex;
        cursor.targetTimestamp = targetTimestamp;
        cursor.initialized = true;
    }

    function binarySearchAll(
        State storage self,
        uint256 targetTimestamp
    )
        internal
        view
        returns (
            uint16 beforeIndex,
            Observation memory beforeOrAt,
            Observation memory atOrAfter
        )
    {
        uint256 l = (self.currentObservationIndex + 1) % MAX_OBSERVATION;
        uint256 r = l + MAX_OBSERVATION - 1;
        uint256 i;

        while (true) {
            i = (l + r) / 2;
            beforeOrAt = self.observations[i % MAX_OBSERVATION];

            if (beforeOrAt.timestamp == 0) {
                l = i + 1;
                continue;
            }

            atOrAfter = self.observations[(i + 1) % MAX_OBSERVATION];

            bool targetAtOrAfter = beforeOrAt.timestamp <= targetTimestamp;
            if (targetAtOrAfter && targetTimestamp <= atOrAfter.timestamp) {
                beforeIndex = uint16(i % MAX_OBSERVATION);
                break;
            }

            if (!targetAtOrAfter) {
                r = i - 1;
            } else {
                l = i + 1;
            }
        }
    }

    function binarySearchLimitedRange(
        State storage self,
        uint256 targetTimestamp,
        uint16 leftIndex,
        uint16 rightIndex
    )
        internal
        view
        returns (
            uint16 beforeIndex,
            Observation memory beforeOrAt,
            Observation memory atOrAfter
        )
    {
        uint256 l = leftIndex;
        uint256 r = rightIndex;
        if (r < l) {
            r += MAX_OBSERVATION;
        }

        uint256 i;
        while (true) {
            i = (l + r) / 2;
            beforeIndex = uint16(i % MAX_OBSERVATION);
            beforeOrAt = self.observations[beforeIndex];

            if (beforeOrAt.timestamp == 0) {
                l = i + 1;
                continue;
            }

            atOrAfter = self.observations[(beforeIndex + 1) % MAX_OBSERVATION];

            bool targetAtOrAfter = beforeOrAt.timestamp <= targetTimestamp;
            if (
                targetAtOrAfter &&
                (atOrAfter.timestamp == 0 ||
                    targetTimestamp <= atOrAfter.timestamp)
            ) {
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
