# Quickswap V3 Vault

## Build and Test with Polygon Mainnet Forking

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
- Polygon mainnet RPC URL (e.g., from Alchemy, Infura, or public node)

---

## Build Contracts

```bash
forge build
```

---

## Run Tests with Mainnet Forking (Polygon)

To run tests against a fork of Polygon mainnet at block 71,668,213:

```bash
forge test \
  --fork-url <YOUR_POLYGON_RPC_URL> \
  --fork-block-number 71668213
```

- Replace `<YOUR_POLYGON_RPC_URL>` with your Polygon mainnet RPC endpoint.
- The `--fork-block-number 71668213` flag ensures deterministic state for your tests.

### Example with Environment Variable

```bash
export POLYGON_RPC_URL="https://polygon-rpc.com"
forge test \
  --fork-url $POLYGON_RPC_URL \
  --fork-block-number 71668213
```

---

## Notes
- Your RPC provider must support archive data at the specified block.
- Forking allows you to test against real mainnet state without deploying contracts.
