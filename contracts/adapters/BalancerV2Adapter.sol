//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAsset, IERC20 as IERC20Balancer, IVault} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {IBasePool} from "@balancer-labs/v2-interfaces/contracts/vault/IBasePool.sol";
import {IPoolSwapStructs} from "@balancer-labs/v2-interfaces/contracts/vault/IPoolSwapStructs.sol";
import {IBalancerV2MinimalSwapInfoPool} from "../interfaces/IBalancerV2MinimalSwapInfoPool.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {DexAdapter} from "./DexAdapter.sol";

/**
 * @title BalancerV2Adapter
 * @author Oddcod3 (@oddcod3)
 */
contract BalancerV2Adapter is DexAdapter, Governable {
    using SafeERC20 for IERC20;

    error BalancerV2Adapter__OutOfBound();
    error BalancerV2Adapter__NotRegisteredVault();
    error BalancerV2Adapter__VaultAlreadyRegistered();
    error BalancerV2Adapter__InvalidPool();

    /// @dev Array of vault addresses registered with the contract.
    address[] private s_vaults;
    /// @dev Mapping to track registration status of each vault.
    mapping(address vault => bool isRegistered) private s_isRegisteredVault;
    /// @dev Nested mapping to store pools associated with specific token pairs for each vault.
    mapping(address token0 => mapping(address token1 => mapping(address vault => address[] pools))) private
        s_tokensToVaultPools;
    /// @dev Mapping to track the index of a token in a liquidity pool.
    mapping(address pool => mapping(address token => uint128 tokenIndex)) private s_poolToTokenIndex;

    constructor(address governor, string memory description) DexAdapter(description) Governable(governor) {}

    /**
     * @dev Registers a new vault with the contract.
     * @param vault The address of the vault to be registered.
     * @notice This function can only be called by the contract's governor and is used to add new vaults to the list of registered vaults.
     *         If the vault is already registered, the function will revert with 'BalancerV2Adapter__VaultAlreadyRegistered'.
     */
    function addVault(address vault) external onlyGovernor {
        if (s_isRegisteredVault[vault]) revert BalancerV2Adapter__VaultAlreadyRegistered();
        s_isRegisteredVault[vault] = true;
        s_vaults.push(vault);
    }

    /**
     * @dev Removes a vault from the list of registered vaults.
     * @param vaultIndex The index of the vault to be removed in the 's_vaults' array.
     * @notice This function can only be called by the contract's governor and is used to unregister vaults by specifying the index on the vaults list.
     *         If the 'vaultIndex' is out of bounds, the function will revert with 'BalancerV2Adapter__OutOfBound'.
     */
    function removeVault(uint256 vaultIndex) external onlyGovernor {
        uint256 vaultsLen = s_vaults.length;
        if (vaultsLen == 0 || vaultIndex >= vaultsLen) revert BalancerV2Adapter__OutOfBound();
        s_isRegisteredVault[s_vaults[vaultIndex]] = false;
        if (vaultIndex < vaultsLen - 1) {
            s_vaults[vaultIndex] = s_vaults[vaultsLen - 1];
        }
        s_vaults.pop();
    }

    /**
     * @dev Registers multiple pools for a specified vault.
     * @param vault The address of the vault for which pools are being registered.
     * @param pools An array of pool addresses to be registered with the vault.
     * @notice This function can only be called by the contract's governor. It associates a set of pools with a given vault.
     *         For each pool, it retrieves the pool's tokens and updates the internal mappings to track the relationship between pools, tokens, and the vault.
     */
    function addVaultPools(address vault, address[] memory pools) external onlyGovernor {
        uint256 poolsLen = pools.length;
        uint256 tokensLen;
        address pool;
        address token;
        IERC20Balancer[] memory tokens;
        for (uint128 i; i < poolsLen;) {
            pool = pools[i];
            (tokens,,) = IVault(vault).getPoolTokens(IBasePool(pool).getPoolId());
            tokensLen = tokens.length;
            for (uint128 j; j < tokensLen;) {
                token = address(tokens[j]);
                s_poolToTokenIndex[pool][token] = j;
                for (uint128 k; k < tokensLen;) {
                    if (j != k) s_tokensToVaultPools[token][address(tokens[k])][vault].push(pool);
                    unchecked {
                        ++k;
                    }
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Unregisters multiple pools from a specified vault.
     * @param vault The address of the vault from which pools are being unregistered.
     * @param pools An array of pool addresses to be unregistered from the vault.
     * @notice This function can only be called by the contract's governor. It dissociates a set of pools from a given vault.
     *         For each pool in the array, it retrieves the pool's tokens and updates the internal mappings to remove the relationship between the pools, tokens, and the vault.
     */
    function removeVaultPools(address vault, address[] memory pools) external onlyGovernor {
        uint256 poolsLen = pools.length;
        uint256 tokensLen;
        address pool;
        address token;
        uint256 registeredPoolsLen;
        address[] storage registeredPools;
        IERC20Balancer[] memory tokens;
        for (uint256 i; i < poolsLen;) {
            pool = pools[i];
            (tokens,,) = IVault(vault).getPoolTokens(IBasePool(pool).getPoolId());
            tokensLen = tokens.length;
            for (uint128 j; j < tokensLen;) {
                token = address(tokens[j]);
                for (uint128 k; k < tokensLen;) {
                    if (j != k) {
                        registeredPools = s_tokensToVaultPools[token][address(tokens[k])][vault];
                        registeredPoolsLen = registeredPools.length;
                        for (uint128 l; l < registeredPoolsLen;) {
                            if (registeredPools[l] == pool) {
                                if (l < registeredPoolsLen - 1) {
                                    registeredPools[l] = registeredPools[registeredPoolsLen - 1];
                                }
                                registeredPools.pop();
                                break;
                            }
                            unchecked {
                                ++l;
                            }
                        }
                    }
                    unchecked {
                        ++k;
                    }
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc DexAdapter
    function _swap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOut,
        bytes memory extraArgs
    ) internal override {
        (address vault, uint256 poolIndex) = abi.decode(extraArgs, (address, uint256));
        if (!s_isRegisteredVault[vault]) revert BalancerV2Adapter__NotRegisteredVault();
        address pool = tokenIn < tokenOut
            ? s_tokensToVaultPools[tokenIn][tokenOut][vault][poolIndex]
            : s_tokensToVaultPools[tokenOut][tokenIn][vault][poolIndex];
        if (pool == address(0)) revert BalancerV2Adapter__InvalidPool();
        IERC20 inputToken = IERC20(tokenIn);
        inputToken.safeTransferFrom(msg.sender, address(this), amountIn);
        inputToken.forceApprove(vault, amountIn);
        IVault.SingleSwap memory swap = IVault.SingleSwap({
            poolId: IBasePool(pool).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn),
            assetOut: IAsset(tokenOut),
            amount: amountIn,
            userData: ""
        });
        IVault.FundManagement memory fund = IVault.FundManagement({
            sender: address(this),
            recipient: payable(to),
            fromInternalBalance: false,
            toInternalBalance: false
        });
        IVault(vault).swap(swap, fund, amountOut, block.timestamp);
    }

    /// @inheritdoc DexAdapter
    function _getMaxOutput(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        override
        returns (uint256 maxOutput, bytes memory extraArgs)
    {
        uint256 vaultsLen = s_vaults.length;
        uint256 poolsLen;
        uint256 tempOutput;
        address vault;
        address pool;
        address[] memory pools;
        IPoolSwapStructs.SwapRequest memory swapRequest;
        swapRequest.kind = IVault.SwapKind.GIVEN_IN;
        swapRequest.tokenIn = IERC20Balancer(tokenIn);
        swapRequest.tokenOut = IERC20Balancer(tokenOut);
        swapRequest.amount = amountIn;
        for (uint256 i; i < vaultsLen;) {
            vault = s_vaults[i];
            pools = tokenIn < tokenOut
                ? s_tokensToVaultPools[tokenIn][tokenOut][vault]
                : s_tokensToVaultPools[tokenOut][tokenIn][vault];
            poolsLen = pools.length;
            for (uint256 j; j < poolsLen;) {
                pool = pools[j];
                swapRequest.poolId = IBasePool(pool).getPoolId();
                tempOutput = _getAmountOut(swapRequest, vault, pool);
                if (tempOutput > maxOutput) {
                    maxOutput = tempOutput;
                    extraArgs = abi.encode(vault, j);
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc DexAdapter
    function _getOutputFromArgs(address tokenIn, address tokenOut, uint256 amountIn, bytes memory extraArgs)
        internal
        view
        override
        returns (uint256 amountOut)
    {
        (address vault, uint256 poolIndex) = abi.decode(extraArgs, (address, uint256));
        address pool = tokenIn < tokenOut
            ? s_tokensToVaultPools[tokenIn][tokenOut][vault][poolIndex]
            : s_tokensToVaultPools[tokenOut][tokenIn][vault][poolIndex];
        if (pool == address(0)) return 0;
        IPoolSwapStructs.SwapRequest memory swapRequest;
        swapRequest.kind = IVault.SwapKind.GIVEN_IN;
        swapRequest.tokenIn = IERC20Balancer(tokenIn);
        swapRequest.tokenOut = IERC20Balancer(tokenOut);
        swapRequest.amount = amountIn;
        swapRequest.poolId = IBasePool(pool).getPoolId();
        return _getAmountOut(swapRequest, vault, pool);
    }

    /// @inheritdoc DexAdapter
    function _getAdapterArgs(address tokenIn, address tokenOut)
        internal
        view
        override
        returns (bytes[] memory extraArgs)
    {
        uint256 vaultsLen = s_vaults.length;
        bytes[][] memory tempArgs = new bytes[][](s_vaults.length);
        uint256 argsLen = 0;
        address vault;
        address[] memory pools;
        for (uint256 i; i < vaultsLen;) {
            vault = s_vaults[i];
            pools = tokenIn < tokenOut
                ? s_tokensToVaultPools[tokenIn][tokenOut][vault]
                : s_tokensToVaultPools[tokenOut][tokenIn][vault];
            uint256 poolsLen = pools.length;
            if (poolsLen > 0) tempArgs[i] = new bytes[](poolsLen);
            for (uint256 j; j < poolsLen;) {
                tempArgs[i][j] = abi.encode(vault, j);
                unchecked {
                    ++j;
                    ++argsLen;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (argsLen > 0) extraArgs = new bytes[](argsLen);
        uint256 extraArgsIndex;
        for (uint256 i; i < vaultsLen;) {
            uint256 poolsLen = tempArgs[i].length;
            for (uint256 j; j < poolsLen;) {
                extraArgs[extraArgsIndex] = tempArgs[i][j];
                unchecked {
                    ++extraArgsIndex;
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Calculates the output amount for a given swap request in a Balancer V2 pool.
     * @param swapRequest A struct containing details about the swap request, including the token in, token out, and the amount in.
     * @param vault The address of the Balancer V2 vault.
     * @param pool The address of the specific Balancer V2 pool where the swap is to be executed.
     * @return amountOut The calculated amount of the output token that will be received from the swap.
     * @notice This function retrieves the balances of the input and output tokens in the specified pool,
     *         then calls the `onSwap` function of the Balancer V2 pool with the swap request and token balances.
     *         If the `onSwap` call fails, the function will return zero.
     */
    function _getAmountOut(IPoolSwapStructs.SwapRequest memory swapRequest, address vault, address pool)
        internal
        view
        returns (uint256 amountOut)
    {
        (, uint256[] memory balances,) = IVault(vault).getPoolTokens(swapRequest.poolId);
        uint256 tokenInPoolBalance = balances[s_poolToTokenIndex[pool][address(swapRequest.tokenIn)]];
        uint256 tokenOutPoolBalance = balances[s_poolToTokenIndex[pool][address(swapRequest.tokenOut)]];
        try IBalancerV2MinimalSwapInfoPool(pool).onSwap(swapRequest, tokenInPoolBalance, tokenOutPoolBalance) returns (
            uint256 amount
        ) {
            amountOut = amount;
        } catch {}
    }

    /**
     * @dev Retrieves the address of a registered vault based on its index in the vaults array.
     * @param vaultIndex The index of the vault in the 's_vaults' array.
     * @return The address of the vault located at the specified index.
     */
    function getVaultAtIndex(uint256 vaultIndex) external view returns (address) {
        return s_vaults[vaultIndex];
    }

    /**
     * @dev Retrieves the pools associated with a specific vault for a given pair of tokens.
     * @param vault The address of the vault.
     * @param token0 The address of the first token in the token pair.
     * @param token1 The address of the second token in the token pair.
     * @return pools An array of pool addresses that are associated with the specified vault and token pair.
     */
    function getVaultPools(address vault, address token0, address token1)
        external
        view
        returns (address[] memory pools)
    {
        return
            token0 < token1 ? s_tokensToVaultPools[token0][token1][vault] : s_tokensToVaultPools[token1][token0][vault];
    }

    /// @return vaultsLength The number of vaults currently registered
    function allVaultsLength() external view returns (uint256) {
        return s_vaults.length;
    }
}
