# 🌐 Multi-Chain Oracle Price Aggregator

_(Powered by Reactive Network)_

## 📖 Overview

The **Multi-Chain Oracle Price Aggregator** is a next-generation, fully on-chain decentralized price feed system. Traditional oracles rely heavily on off-chain components (like keeper bots or centralized servers) to fetch, calculate, and push data to the blockchain.

This project completely eliminates off-chain dependencies by utilizing the **Reactive Network**. It acts as an autonomous, cross-chain hub that actively listens to decentralized exchanges (DEXs) across multiple blockchains, aggregates the pricing data in real-time, and securely delivers a unified price to a destination smart contract.

---

## 🏗 System Architecture

The architecture is designed to be trustless, event-driven, and highly resilient against localized market manipulation. It operates through three distinct layers:

### 1. The Data Source Layer (Origin Chains)

This layer consists of the actual decentralized markets where trading happens.

- **Target:** High-liquidity AMM pools (e.g., Uniswap V3/V4) on various networks like Ethereum Mainnet, Arbitrum, Optimism, and Base.
- **Mechanism:** Every time a trade occurs in these pools, the smart contracts emit on-chain events (such as `Swap` events) that contain the latest tick or price data.
- **Role:** These disparate pools act as independent, raw data providers.

### 2. The Aggregation Hub (Reactive Network)

This is the core engine of the system, deployed entirely on the Reactive Network. It operates without any human or bot intervention.

- **Event Subscription:** The hub is configured to "listen" concurrently to the specific `Swap` events from the pools defined in the Source Layer.
- **Data Processing:** When a relevant event is detected, the Reactive Virtual Machine (RVM) automatically spins up. It catches the emitted price data (e.g., the current tick) and buffers it.
- **Consensus & Aggregation:** The hub takes the latest price points from all monitored chains and applies an aggregation algorithm (such as calculating the Median or a Time-Weighted Average Price - TWAP). This neutralizes anomalies or flash-loan manipulations that might occur on a single isolated chain.

### 3. The Consumer Layer (Destination Chain)

This is where the final, sanitized data is utilized.

- **Target:** A specific destination network where your DeFi applications (Lending protocols, Derivatives, Synthetic assets) reside.
- **Mechanism:** Once the hub calculates a new valid aggregated price, it triggers a cross-chain **Callback**.
- **Role:** The callback pushes the finalized price directly into a designated Consumer Oracle Smart Contract on the destination chain, making it immediately available for dApps to read and execute logic against.

---

## ✨ Key Advantages

- **True Multi-Chain Consensus:** By sourcing liquidity and pricing data from multiple isolated networks into a single computational hub, the system reflects the true global market price of an asset.
- **100% Botless Automation:** Eliminates the Single Point of Failure (SPOF) associated with Web2 infrastructure. There are no cronjobs, keeper bots, or external servers to maintain or trust.
- **Manipulation Resistance:** An attacker would need to simultaneously manipulate highly liquid pools across multiple different blockchains to significantly alter the aggregated price, making economic exploits virtually impossible.
