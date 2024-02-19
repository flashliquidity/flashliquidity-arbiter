// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IArbiter
 * @author Oddcod3 (@oddcod3)
 */
interface IArbiter {
    /**
     * @dev Sets the verifier proxy address for Chainlink Data Streams.
     * @param verifierProxy The address of the new verifier proxy.
     */
    function setVerifierProxy(address verifierProxy) external;

    /**
     * @dev Updates the maximum allowed staleness for price data from Chainlink Data Feeds.
     * @param priceMaxStaleness The new maximum duration (in seconds) that price data is considered valid.
     * @notice This function sets the threshold for how old the price data from Chainlink Data Feeds can be before it's considered stale.
     */
    function setPriceMaxStaleness(uint32 priceMaxStaleness) external;

    /**
     * @dev Registers Chainlink data feeds for specific tokens.
     * @param tokens An array of token addresses for which data feeds are to be registered.
     * @param dataFeeds An array of Chainlink data feed addresses, each corresponding to a token address in the 'tokens' array.
     * @notice This function is used to link each token with its respective Chainlink data feed.
     * @notice The 'tokens' and 'dataFeeds' arrays must have the same length, ensuring each data feed is mapped to its associated token address
     */
    function setDataFeeds(address[] calldata tokens, address[] calldata dataFeeds) external;

    /**
     * @dev Registers Chainlink data streams for specific tokens.
     * @param tokens An array of token addresses for which data streams are to be registered.
     * @param feedIDs An array of Chainlink data stream IDs, each corresponding to a token address in the 'tokens' array.
     * @notice This function establishes a link between each token and its corresponding Chainlink data stream.
     * @notice The 'tokens' and 'feedIDs' arrays must have the same length, ensuring each data stream ID is mapped to its associated token address.
     */
    function setDataStreams(address[] calldata tokens, string[] calldata feedIDs) external;

    /**
     * @dev Registers an Arbiter job to monitor a specific self-balancing pool for rebalancing needs.
     * @param selfBalancingPool The address of the self-balancing pool to be monitored.
     * @param rewardVault The address of the reward vault where rebalancing profits will be deposited.
     * @param minProfitUSD The minimum profit in USD (with 8 decimals) required to trigger a rebalancing operation.
     * @param forceToken0Decimals The decimal count to be used for token0, especially for non-standard ERC20 tokens that do not comply with the IERC20Metadata interface.
     * @param forceToken1Decimals The decimal count to be used for token1, especially for non-standard ERC20 tokens that do not comply with the IERC20Metadata interface.
     * @notice Set 'forceToken0Decimals' and 'forceToken1Decimals' to zero to default to the ERC20 decimal values provided by the decimals() function of each token.
     */
    function setArbiterJob(
        address selfBalancingPool,
        address rewardVault,
        uint96 minProfitUSD,
        uint8 forceToken0Decimals,
        uint8 forceToken1Decimals
    ) external;

    /**
     * @dev Removes a previously registered Arbiter job associated with a specific self-balancing pool.
     * @param selfBalancingPool The address of the self-balancing pool whose corresponding Arbiter job is to be deleted.
     * @notice This function is used to deregister an Arbiter job that is no longer needed.
     */
    function deleteArbiterJob(address selfBalancingPool) external;

    /**
     * @dev Adds a new adapter to the Arbiter's list of adapters.
     * @param adapter The address of the new adapter to be added.
     */
    function pushDexAdapter(address adapter) external;

    /**
     * @dev Removes an adapter from the Arbiter's list of adapters using its index.
     * @param adapterIndex The index (position) of the adapter in the Arbiter's adapter list that is to be removed.
     * @notice It's important to ensure that the index provided is correct, otherwise the wrong adapter will be removed.
     */
    function removeDexAdapter(uint256 adapterIndex) external;

    /**
     * @dev Allows for the recovery of ERC20 tokens from the contract.
     * @param to The address to which the recovered tokens will be sent.
     * @param tokens An array of ERC20 token addresses that are to be recovered.
     * @param amounts An array of amounts for each token to be recovered. The array index corresponds to the token address in the 'tokens' array.
     * @notice This function is typically used in cases where tokens are accidentally sent to the contract or for withdrawing excess tokens. 
     */
    function recoverERC20(address to, address[] memory tokens, uint256[] memory amounts) external;

    /**
     * @dev Implements the callback function that is triggered by swap operations in FlashLiquidity pools.
     * @param sender The address that initiated the swap, thereby triggering this callback function.
     * @param amount0 The amount of token0 obtained as a result of the swap.
     * @param amount1 The amount of token1 obtained as a result of the swap.
     * @param data Encoded data in the form of a CallbackData struct, containing instructions for the rebalancing operation to be executed on another DEX.
     * @notice This function will revert under two conditions: if the 'sender' is not the authorized arbiter, or if the `msg.sender` is not the permitted pair address for the swap.
     * @notice It is essential for security that only authorized entities can trigger and execute this callback to prevent unauthorized or malicious use.
     */
    function flashLiquidityCall(address sender, uint256 amount0, uint256 amount1, bytes memory data) external;

    /// @return verifierProxy The address of Chainlink Data Streams verifier proxy.
    function getVerifierProxy() external view returns (address verifierProxy);

    /// @return priceMaxStaleness The maximum duration (in seconds) that Chainlink Data Feed price data is considered valid.
    function getPriceMaxStaleness() external view returns (uint256 priceMaxStaleness);

    /**
     * @dev Retrieves information about a specific Arbiter job associated with a self-balancing pool.
     * @param selfBalancingPool The address of the self-balancing pool associated with the Arbiter job to be retrieved.
     * @return rewardVault The address of the reward vault where rebalancing profits are deposited.
     * @return minProfitUSD The minimum profit in USD (with 8 decimals) required to trigger a rebalancing operation.
     * @return token0 The address of token0 in the self-balancing pool.
     * @return token1 The address of token1 in the self-balancing pool.
     * @return token0Decimals The number of decimals for token0.
     * @return token1Decimals The number of decimals for token1.
     * @notice This function provides detailed information about the configuration of a specific Arbiter job.
     */
    function getJobConfig(address selfBalancingPool)
        external
        view
        returns (
            address rewardVault,
            uint96 minProfitUSD,
            address token0,
            address token1,
            uint8 token0Decimals,
            uint8 token1Decimals
        );

    /// @param token The address of the token for which the Chainlink Data Feed address is to be retrieved.
    /// @return dataFeed The address of the Chainlink Data Feed associated with the specified 'token'.
    function getDataFeed(address token) external view returns (address dataFeed);

    /// @param token The address of the token for which the Chainlink Data Stream ID is to be retrieved.
    /// @return feedID The ID of the Chainlink Data Stream associated with the specified 'token'.
    function getDataStream(address token) external view returns (string memory feedID);

    /// @param adapterIndex The index (position) of the adapter in the Arbiter's adapters list.
    /// @return adapter The address of the adapter located at the specified 'adapterIndex' in the list.
    function getDexAdapter(uint256 adapterIndex) external view returns (address adapter);

    /// @return adaptersLength The number of adapters currently registered
    function allAdaptersLength() external view returns (uint256 adaptersLength);
}
