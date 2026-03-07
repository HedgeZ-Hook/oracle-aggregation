# Reactive Perp Liquidator & Cross-Chain Oracle

## Overview

The **Reactive Perp Liquidator** is a next-generation, fully on-chain automation engine designed for Perpetual Futures protocols. Traditional perpetual DEXs rely heavily on off-chain "Keeper Bots" to monitor user positions and trigger liquidations when collateral ratios drop.
This project eliminates the need for centralized keeper infrastructure. By leveraging the **Reactive Network**, this system autonomously aggregates cross-chain index prices for perpetual assets (sourcing from Chainlink, Pyth, and Uniswap V3/V4 hooks) while concurrently monitoring user position states on **Unichain**. The moment an aggregated price moves against a user's position and breaches the liquidation threshold, the Reactive contract instantly fires a cross-chain execution to liquidate the user directly within the Unichain `vamm-perp-hook`.

---

## System Architecture

The architecture is designed to be trustless, event-driven, and highly resilient. It operates through four interconnected layers:

### 1. The Price Discovery Layer (Cross-Chain Oracles)

This layer provides the raw, real-time pricing data for the assets being traded on the perpetual exchange.

- **Sources:** Chainlink `AnswerUpdated` events, Pyth Network price feeds, and Uniswap V3/V4 `Swap` events (or specific V4 hooks).
- **Networks:** Spread across multiple blockchains (Ethereum, Arbitrum, Optimism, etc.) to ensure robust, manipulation-resistant index pricing.
- **Role:** Continuously emits on-chain price updates that represent the true global market value of the perpetual assets.

### 2. The State Monitoring Layer (Unichain Positions)

This layer tracks the financial health of the traders.

- **Target:** The `vamm-perp-hook` deployed on **Unichain**.
- **Mechanism:** Whenever a user opens, modifies, or closes a leveraged position, the hook emits specific state events (e.g., `PositionOpened`, `MarginUpdated`).
- **Role:** Provides the Reactive Network with the exact entry prices, leverage, and margin balances of all active traders.

### 3. The Reactive Engine (The Hub)

Deployed entirely on the Reactive Network, this is the "brain" of the operation. It requires no human intervention or off-chain servers.

- **Dual-Subscription:** It subscribes to _both_ the Price Discovery events (Layer 1) and the Position State events (Layer 2).
- **Data Processing & Aggregation:** It aggregates the incoming prices from Chainlink, Pyth, and Uniswap to form a secure "Mark Price". Simultaneously, it maintains a real-time internal ledger of user positions.
- **Health Evaluation:** Upon every price update, the Reactive Virtual Machine (RVM) calculates the Health Factor of the tracked positions.

### 4. The Execution Layer (Automated Liquidation)

This is where the autonomous action takes place.

- **Trigger:** If the hub detects that a user's Health Factor has dropped below the maintenance margin requirement (Health Factor < 1.0), it immediately halts further monitoring for that user.
- **Callback Execution:** The hub crafts a payload and triggers a cross-chain callback targeted at the `vamm-perp-hook` on Unichain.
- **Result:** The callback calls the `liquidatePosition(address user)` function on the hook, successfully closing the underwater position, protecting the protocol from bad debt, and earning the liquidation bounty for the contract.

---

## Key Advantages

- **Zero-Bot Infrastructure:** Replaces unreliable, gas-war-prone Web2 keeper bots with a deterministic, protocol-level automation network.
- **Manipulation-Proof Indexing:** By aggregating prices cross-chain from premium oracles (Chainlink/Pyth) and deep liquidity DEXs (Uni V3/V4), the system prevents localized flash-loan attacks from causing unfair liquidations.
- **Instantaneous Reaction:** The moment a price update event pushes a position into bankruptcy territory, the liquidation callback is fired in the very next available execution cycle.
- **De-Risking the Protocol:** Ensures the perpetual exchange remains solvent without relying on third-party liquidators to be online during periods of extreme network congestion.
