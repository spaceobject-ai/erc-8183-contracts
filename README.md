# ERC-8183: Agentic Commerce

Reference implementation of [ERC-8183](https://eips.ethereum.org/EIPS/eip-8183) — a Job primitive for trustless agent commerce. Its core features are a job escrow protocol with evaluator attestation and an optional hook system for extensibility.

This is the [SpaceObject](https://github.com/spaceobject-ai) fork of [`erc-8183/base-contracts`](https://github.com/erc-8183/base-contracts). No proxy is live yet. After the first broadcast, put the addresses in the [deployment](#deployment) table.

## Quick Start

Requires [Foundry](https://getfoundry.sh/). Compiler is solc 0.8.28, EVM Cancun. See [foundry.toml](foundry.toml).

```shell
forge install
forge build
forge test
```

## Overview

ERC-8183 defines a minimal on-chain job escrow between three roles:

- **Client** — creates and funds jobs
- **Provider** — delivers work
- **Evaluator** — attests to completion or rejects

The core state machine:

```
Open → Funded → Submitted → Completed | Rejected | Expired
```

Each transition enforces role-based access control, and funds are held in escrow until the evaluator completes or the job is rejected/expired.

## Hook System

Jobs can optionally attach a **hook contract** (`IERC8183Hook`) to extend behavior without modifying the core:

- `beforeAction` — called before state changes, can revert to gate transitions
- `afterAction` — called after state changes, for bookkeeping and side effects

When `hook == address(0)`, the contract operates as a standalone job escrow with no callbacks. See [docs/02-hook-system.md](docs/02-hook-system.md) for the full design.

## What changed

The latest merge on this fork is [#1](https://github.com/spaceobject-ai/erc-8183-contracts/pull/1) (`fb0695d`). Event ABIs differ from upstream [`erc-8183/base-contracts`](https://github.com/erc-8183/base-contracts).

**JobCreated.** The log now includes `providerAgentId` and `description`. When the client sets the provider at creation, `ProviderSet` does not fire, so indexers could not recover the brief or agent id from logs alone. If `provider` is unset, `providerAgentId` is emitted as 0.

**Payment token on value-moving events.** `JobFunded`, `PaymentReleased`, `Disbursed`, `PlatformFeePaid`, `EvaluatorFeePaid`, `Refunded`, and `Settled` now index the ERC-20. Those logs used to omit the token, so a consumer had to join `BudgetSet`.

Claim logs (`ClaimSubmitted`, `ClaimSettled`, `ClaimApproved`, `ClaimRejected`) still omit the token. They emit in the same transaction as `Settled` when value moves.

Tests pin `Refunded`, `PlatformFeePaid`, and `EvaluatorFeePaid` argument order so a field slip fails CI.

If you already indexed the upstream ABI, update those event signatures before pointing at this fork.

## Deployment

| Network | Chain ID | Proxy | Implementation | Admin | Treasury |
| --- | --- | --- | --- | --- | --- |
| `arc-testnet` | 5042002 | [`0x85A21c175655BeBc21F4727bE480Fec57Cd18b1a`](https://testnet.arcscan.app/address/0x85A21c175655BeBc21F4727bE480Fec57Cd18b1a) | [`0x59FA29564cD6F2084246eAaAB99DB9453D7B5417`](https://testnet.arcscan.app/address/0x59FA29564cD6F2084246eAaAB99DB9453D7B5417) | `0x6CD4652887e41142Dd7e9FD2dA720809685Def2D` | `0x6CD4652887e41142Dd7e9FD2dA720809685Def2D` |

[script/Deploy.s.sol](script/Deploy.s.sol) deploys `ERC8183WithAuthorization`, the core plus EIP-712 relayed entrypoints. Swap the contract in that file if you want `ERC8183` only.

### Run the script

```shell
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

Dry run without `--broadcast`. The signer pays gas. It does not need to be `ADMIN` unless `PAYMENT_TOKEN` is set.

### After deploy

1. `setPaymentTokenAllowed(token, true)` for each payment token.
2. `setHookWhitelist(hook, true)` for each hook other than `address(0)`.
3. `setPlatformFee` and `setEvaluatorFee` if fees should be nonzero. Combined basis points cannot exceed 10000.
4. Write proxy, implementation, admin, and treasury into the table above.

Upgrades are UUPS. `DEFAULT_ADMIN_ROLE` calls `upgradeToAndCall` on the proxy. If you later swap a live `ERC8183` proxy to `ERC8183WithAuthorization`, the admin must call `initializeAuthorizationV2()` once so EIP-712 storage is set.

## Contracts

```
contracts/
├── ERC8183.sol                 # Core state machine, escrow, fees, hooks
├── ERC8183WithAuthorization.sol # EIP-712 authorization extension for relayed calls
├── IDisburser.sol              # Optional payout receiver callback interface
├── IERC8183Hook.sol            # Hook interface (beforeAction/afterAction)
└── mocks/
    ├── MockUSDC.sol            # Test ERC20, 6 decimals
    ├── MockCBBTC.sol           # Test ERC20, 8 decimals
    ├── MockDisburser.sol       # Test payout receiver and reentrancy callbacks
    ├── MockFeeOnTransferToken.sol  # Test ERC20 that takes a transfer fee (used to verify rejection)
    └── MockERC1271NonceObserver.sol # Test ERC-1271 signer helpers
```

## Architecture

- **Upgradeable** — UUPS proxy pattern via OpenZeppelin
- **Access control** — role-based admin for fees, hook whitelisting, and payment token allowlisting
- **Pausable** — admin can pause user-facing lifecycle functions and use `emergencyWithdraw` while paused
- **CEI pattern** — checks, effects, interactions throughout
- **Reentrancy protection** — transient storage guard on fund-moving and hook-calling lifecycle functions
- **Payment token allowlist** — only admin-vetted ERC-20s can be used as payment tokens
- **Fee-on-transfer / rebasing rejection** — `fund` snapshots the contract balance and reverts if the received amount differs from the budget
- **Evaluator grace period** — after expiry, a Submitted job cannot be force-refunded for `EVALUATION_GRACE_PERIOD` (1 hour), giving the evaluator time to complete or reject
- **Claim settlement fees** — direct settlements and approved claims both use the configured platform/evaluator fee split for the settled delta
- **Streaming settlement independence** — direct `settleClaim` calls can continue while a provider milestone claim is pending; the pending claim stays open until explicitly resolved
- **Pending claim resolution** — after expiry, a Funded job with a pending provider claim cannot be force-refunded until the claim is approved, rejected, or withdrawn; if all parties stay idle, escrow remains parked
- **Claim replay guard** — rejected claim hashes stay consumed, so providers must vary `cumulativeAmount`, the deliverable, or `optParams` to refile
- **Authorization extension** — `ERC8183WithAuthorization` uses the base `ERC8183` EIP-712 domain so relayed entrypoints extend the same protocol identity; signers can call `cancelAuthorization` directly to burn one of their own outstanding nonces
- **Hook safety** — `claimRefund` is intentionally not hookable; pending claims must be resolved before refund

See [docs/01-architecture.md](docs/01-architecture.md) for state machine and sequence diagrams.

## Documentation

- [Architecture & Diagrams](docs/01-architecture.md) — state machine, sequence flows
- [Hook System Design](docs/02-hook-system.md) — IERC8183Hook interface, safety model, invocation pattern
- [Demo Flows](docs/03-demo-flows.md) — end-to-end example scenarios

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Open implementation PRs here. Take protocol changes to the ERC-8183 maintainers.

## License

MIT
