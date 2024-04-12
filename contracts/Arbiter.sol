//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {StreamsLookupCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/StreamsLookupCompatibleInterface.sol";
import {VerifierProxy} from "@chainlink/contracts/src/v0.8/llo-feeds/VerifierProxy.sol";
import {FeeManager} from "@chainlink/contracts/src/v0.8/llo-feeds/FeeManager.sol";
import {Common} from "@chainlink/contracts/src/v0.8/llo-feeds/libraries/Common.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Babylonian} from "./libraries/Babylonian.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {IArbiter} from "./interfaces/IArbiter.sol";
import {IDexAdapter} from "./interfaces/IDexAdapter.sol";
import {IFlashLiquidityPair} from "./interfaces/IFlashLiquidityPair.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";

/**
 * @title Arbiter
 * @author Oddcod3 (@oddcod3)
 * @dev An arbitrage bot designed for performing rebalancing operations and distributing profits to liquidity providers in FlashLiquidity self-balancing pools.
 *      It integrates with Chainlink Automation (via AutomationCompatibleInterface) for triggering rebalancing operations based on predefined conditions, and with Chainlink Data Feeds/Data Streams for fetching price data necessary for these operations.
 * @notice The contract is Governable, implying that certain functionalities are restricted to the contract's governor.
 */
contract Arbiter is IArbiter, AutomationCompatibleInterface, StreamsLookupCompatibleInterface, Governable {
    using SafeERC20 for IERC20;
    ///////////////////////
    // Errors            //
    ///////////////////////

    error Arbiter__InvalidPool();
    error Arbiter__NotManager();
    error Arbiter__InconsistentParamsLength();
    error Arbiter__NotPermissionedPair();
    error Arbiter__InvalidProfitToReservesRatio();
    error Arbiter__InsufficentProfit();
    error Arbiter__NotFromArbiter();
    error Arbiter__NotFromForwarder();
    error Arbiter__DataFeedNotSet();
    error Arbiter__InvalidPrice();
    error Arbiter__StalenessTooHigh();
    error Arbiter__OutOfBound();

    ///////////////////////
    // Types             //
    ///////////////////////

    struct ArbiterJobConfig {
        address rewardVault; // Address of the vault where rebalancing profits are deposited.
        uint96 reserveToMinProfit; // The minimum ratio between reserve and profit below which the rebalancing operation reverts.
        address automationForwarder; // Intermediary between the Chainlink Automation Registry and the Arbiter.
        uint96 reserveToTriggerProfit; // The minimum ratio between reserve and profit required to trigger a rebalancing operation.
        address tokenIn; // Address of the input token for the rebalancing trade.
        uint8 tokenInDecimals; // Decimal count of the input token.
        address tokenOut; // Address of the output token for the rebalancing trade.
        uint8 tokenOutDecimals; // Decimal count of the output token.
    }

    struct ArbiterCall {
        address selfBalancingPool; // Address of the self-balancing pool involved in the trade.
        uint256 amountIn; // Amount of the input token to be used in the trade.
        uint256 amountOut; // Expected amount of the output token from the trade.
        uint256 adapterIndex; // Index of the chosen DEX adapter for the trade.
        bytes extraArgs; // Additional arguments required by the DEX adapter, encoded in bytes.
        bool zeroToOne; // Direction of the swap; true for tokenIn to tokenOut, false for tokenOut to tokenIn.
    }

    struct CallbackData {
        address token0; // Address of the first token in the swap pair.
        address token1; // Address of the second token in the swap pair.
        address rewardVault; // Address of the rewards vault to send profit to.
        uint256 minProfitTokenIn; // The minimum profit denominated in tokenIn below which the rebalancing operation reverts.
        uint256 adapterIndex; // Index of the adapter used for the swap.
        uint256 amountDebt; // Amount of the debt that needs to be returned to the self-balancing pool.
        bytes extraArgs; // Additional encoded arguments required for post-swap operations.
        bool zeroToOne; // Direction of the swap; true for token0 to token1, false for token1 to token0.
    }

    struct PremiumReport {
        bytes32 feedId; // The feed ID the report has data for.
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable.
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable.
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH).
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK.
        uint32 expiresAt; // Latest timestamp where the report can be verified onchain.
        int192 price; // DON consensus median price, carried to 8 decimal places.
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation.
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation.
    }

    struct RebalancingInfo {
        bool zeroToOne; // Direction of the rebalancing swap; true for tokenIn to tokenOut, false otherwise.
        uint256 amountIn; // Amount of the input token to be swapped.
        uint256 amountOut; // Amount of the output token expected from the swap.
    }

    ///////////////////////
    // State Variables   //
    ///////////////////////

    /// @dev FlashLiquidity self-balancing pool fee numerator, set to 9994 to represent a fee of 6 basis points.
    uint24 public constant FL_FEE_NUMERATOR = 9994;
    /// @dev FlashLiquidity self-balancing pool fee denominator, set to 10000 for fee calculation.
    uint24 public constant FL_FEE_DENOMINATOR = 10000;
    /// @dev The address of the Chainlink Data Streams verifier proxy used for verifying signed reports.
    address private s_verifierProxy;
    /// @dev The address that is permissioned for flashLiquidityCall callback verification. Set to a default value.
    address private s_permissionedPairAddress = address(1);
    /// @dev The address of LINK token used to pay for Data Streams reports verification.
    address private immutable i_linkToken;
    /// @dev Maximum staleness allowed for price data in seconds. Prices older than this will be considered invalid.
    uint32 private s_priceMaxStaleness;
    /// @dev Array of DEX adapter interfaces used for handling token swaps.
    IDexAdapter[] private s_adapters;
    /// @dev Mapping from each self-balancing pool address to its corresponding Arbiter job configuration.
    mapping(address selfBalancingPool => ArbiterJobConfig jobConfig) private s_jobConfig;
    /// @dev Mapping of token addresses to their respective Chainlink Data Feeds interfaces.
    mapping(address token => AggregatorV3Interface dataFeed) private s_dataFeeds;
    /// @dev Mapping of token addresses to their respective Chainlink Data Streams IDs.
    mapping(address token => string feedID) private s_dataStreams;

    ///////////////////////
    // Events            //
    ///////////////////////

    event VerifierProxyChanged(address verifierProxy);
    event FeeManagerChanged(address feeManager);
    event PriceMaxStalenessChanged(uint256 newStaleness);
    event NewArbiterJob(address indexed selfBalancingPool, address indexed rewardVault);
    event ArbiterJobRemoved(address indexed selfBalancingPool);
    event NewDexAdapter(address adapter);
    event DexAdapterRemoved(address adapter);
    event DataFeedsChanged(address[] tokens, address[] dataFeeds);
    event DataStreamsChanged(address[] tokens, string[] feedIDs);

    ////////////////////////
    // Functions          //
    ////////////////////////

    constructor(address governor, address verifierProxy, address linkToken, uint32 priceMaxStaleness)
        Governable(governor)
    {
        _setVerifierProxy(verifierProxy);
        _setPriceMaxStaleness(priceMaxStaleness);
        i_linkToken = linkToken;
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    /// @inheritdoc IArbiter
    function setVerifierProxy(address verifierProxy) external onlyGovernor {
        _setVerifierProxy(verifierProxy);
    }

    /// @inheritdoc IArbiter
    function setPriceMaxStaleness(uint32 priceMaxStaleness) external onlyGovernor {
        _setPriceMaxStaleness(priceMaxStaleness);
    }

    /// @inheritdoc IArbiter
    function setDataFeeds(address[] calldata tokens, address[] calldata dataFeeds) external onlyGovernor {
        uint256 tokensLen = tokens.length;
        if (tokensLen != dataFeeds.length) revert Arbiter__InconsistentParamsLength();
        for (uint256 i; i < tokensLen;) {
            s_dataFeeds[tokens[i]] = AggregatorV3Interface(dataFeeds[i]);
            unchecked {
                ++i;
            }
        }
        emit DataFeedsChanged(tokens, dataFeeds);
    }

    /// @inheritdoc IArbiter
    function setDataStreams(address[] calldata tokens, string[] calldata feedIDs) external onlyGovernor {
        uint256 tokensLen = tokens.length;
        if (tokensLen != feedIDs.length) revert Arbiter__InconsistentParamsLength();
        for (uint256 i; i < tokensLen;) {
            s_dataStreams[tokens[i]] = feedIDs[i];
            unchecked {
                ++i;
            }
        }
        emit DataStreamsChanged(tokens, feedIDs);
    }

    /// @inheritdoc IArbiter
    function setArbiterJob(
        address selfBalancingPool,
        address rewardVault,
        address automationForwarder,
        uint96 reserveToMinProfit,
        uint96 reserveToTriggerProfit,
        uint8 forceToken0Decimals,
        uint8 forceToken1Decimals
    ) external onlyGovernor {
        IFlashLiquidityPair flPool = IFlashLiquidityPair(selfBalancingPool);
        (address token0, address token1) = (flPool.token0(), flPool.token1());
        if (token0 == address(0) || token1 == address(0)) revert Arbiter__InvalidPool();
        if (flPool.manager() != address(this)) revert Arbiter__NotManager();
        if (address(s_dataFeeds[token0]) == address(0) || address(s_dataFeeds[token1]) == address(0)) {
            revert Arbiter__DataFeedNotSet();
        }
        if (reserveToMinProfit == 0 || reserveToTriggerProfit == 0 || reserveToMinProfit > reserveToTriggerProfit) {
            revert Arbiter__InvalidProfitToReservesRatio();
        }
        if (reserveToMinProfit < reserveToTriggerProfit - reserveToTriggerProfit / 10) {
            revert Arbiter__InvalidProfitToReservesRatio();
        }
        s_jobConfig[selfBalancingPool] = ArbiterJobConfig({
            rewardVault: rewardVault,
            reserveToMinProfit: reserveToMinProfit,
            automationForwarder: automationForwarder,
            reserveToTriggerProfit: reserveToTriggerProfit,
            tokenIn: token0,
            tokenInDecimals: forceToken0Decimals > 0 ? forceToken0Decimals : IERC20Metadata(token0).decimals(),
            tokenOut: token1,
            tokenOutDecimals: forceToken1Decimals > 0 ? forceToken1Decimals : IERC20Metadata(token1).decimals()
        });
        emit NewArbiterJob(selfBalancingPool, rewardVault);
    }

    /// @inheritdoc IArbiter
    function deleteArbiterJob(address selfBalancingPool) external onlyGovernor {
        delete s_jobConfig[selfBalancingPool];
        emit ArbiterJobRemoved(selfBalancingPool);
    }

    /// @inheritdoc IArbiter
    function pushDexAdapter(address adapter) external onlyGovernor {
        s_adapters.push(IDexAdapter(adapter));
        emit NewDexAdapter(adapter);
    }

    /// @inheritdoc IArbiter
    function removeDexAdapter(uint256 adapterIndex) external onlyGovernor {
        uint256 adaptersLen = s_adapters.length;
        if (adaptersLen == 0 || adapterIndex >= adaptersLen) revert Arbiter__OutOfBound();
        address dexAdapter = address(s_adapters[adapterIndex]);
        if (adapterIndex < adaptersLen - 1) {
            s_adapters[adapterIndex] = s_adapters[adaptersLen - 1];
        }
        s_adapters.pop();
        emit DexAdapterRemoved(dexAdapter);
    }

    /// @inheritdoc IArbiter
    function recoverERC20(address to, address[] memory tokens, uint256[] memory amounts) external onlyGovernor {
        uint256 tokensLen = tokens.length;
        if (tokensLen != amounts.length) revert Arbiter__InconsistentParamsLength();
        for (uint256 i; i < tokensLen;) {
            IERC20(tokens[i]).safeTransfer(to, amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IArbiter
     * @dev This function is called post-flash swap inside performUpkeep call to handle the received tokens.
     *
     * The function performs the following operations:
     * 1. Decodes the `data` to retrieve `CallbackData` which contains swap details and profit targets.
     * 2. Determines the direction of the swap and sets the corresponding token amounts for the swap.
     * 3. Executes the swap via the specified DEX adapter using the amounts and parameters from `CallbackData`.
     * 4. Calculates the profit from the swap and ensures it meets the minimum profit threshold specified in `CallbackData`.
     * 5. Distributes the profit to the designated `rewardVault` and returns the borrowed amount to the self-balancing pool.
     *
     * Reverts if:
     * - The call is not from the expected permissioned pair address (`msg.sender` check).
     * - The sender is not the Arbiter contract itself.
     * - The calculated profit does not meet the minimum required profit threshold.
     *
     */
    function flashLiquidityCall(address sender, uint256 amount0, uint256 amount1, bytes memory data) external {
        if (msg.sender != s_permissionedPairAddress) revert Arbiter__NotPermissionedPair();
        if (sender != address(this)) revert Arbiter__NotFromArbiter();
        CallbackData memory info = abi.decode(data, (CallbackData));
        (IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) = info.zeroToOne
            ? (IERC20(info.token1), IERC20(info.token0), amount1)
            : (IERC20(info.token0), IERC20(info.token1), amount0);
        IDexAdapter adapter = s_adapters[info.adapterIndex];
        tokenIn.forceApprove(address(adapter), amountIn);
        uint256 amoutOut = adapter.swap(address(tokenIn), address(tokenOut), address(this), amountIn, 0, info.extraArgs);
        uint256 profit = amoutOut - info.amountDebt;
        if (profit < info.minProfitTokenIn) revert Arbiter__InsufficentProfit();
        tokenOut.safeTransfer(info.rewardVault, profit);
        tokenOut.safeTransfer(msg.sender, info.amountDebt);
    }

    /**
     * @inheritdoc AutomationCompatibleInterface
     * @dev Executes the upkeep routine as part of the Chainlink Automation integration.
     * @param performData Encoded data necessary for the upkeep, which includes signed reports and Arbiter call details.
     *
     * In the function:
     * 1. It decodes `performData` to extract signed reports and the ArbiterCall struct.
     * 2. Retrieves the job configuration for the self-balancing pool involved in the call.
     * 3. Sets the permissioned pair address to the self-balancing pool address for validation.
     * 4. Prepares callback data for the swap operation.
     * 5. Verifies data stream reports if present.
     * 6. Performs the swap operation via the self-balancing pool.
     * 7. Resets the permissioned pair address.
     *
     * @notice This function is crucial for the automated rebalancing of pools and is triggered by Chainlink Automation.
     * @notice It ensures that each swap is profitable and adheres to the configured parameters of the job.
     */
    function performUpkeep(bytes calldata performData) external override {
        (bytes[] memory signedReports, ArbiterCall memory call) = abi.decode(performData, (bytes[], ArbiterCall));
        ArbiterJobConfig memory jobConfig = s_jobConfig[call.selfBalancingPool];
        if (msg.sender != jobConfig.automationForwarder) revert Arbiter__NotFromForwarder();
        if (signedReports.length != 0) _verifyDataStreamReports(signedReports);
        s_permissionedPairAddress = call.selfBalancingPool;
        (uint256 reserve0, uint256 reserve1,) = IFlashLiquidityPair(call.selfBalancingPool).getReserves();
        (uint256 amount0, uint256 amount1, uint256 reserveTokenIn) =
            call.zeroToOne ? (uint256(0), call.amountOut, reserve0) : (call.amountOut, uint256(0), reserve1);
        CallbackData memory callbackData = CallbackData({
            token0: jobConfig.tokenIn,
            token1: jobConfig.tokenOut,
            rewardVault: jobConfig.rewardVault,
            minProfitTokenIn: reserveTokenIn / jobConfig.reserveToMinProfit,
            adapterIndex: call.adapterIndex,
            amountDebt: call.amountIn,
            extraArgs: call.extraArgs,
            zeroToOne: call.zeroToOne
        });
        IFlashLiquidityPair(call.selfBalancingPool).swap(amount0, amount1, address(this), abi.encode(callbackData));
        s_permissionedPairAddress = address(1);
    }

    ////////////////////////
    // Private Functions  //
    ////////////////////////

    /// @param verifierProxy The address of the new verifier proxy.
    function _setVerifierProxy(address verifierProxy) private {
        s_verifierProxy = verifierProxy;
        emit VerifierProxyChanged(verifierProxy);
    }

    /// @param priceMaxStaleness The new maximum duration (in seconds) that price data is considered valid.
    function _setPriceMaxStaleness(uint32 priceMaxStaleness) private {
        s_priceMaxStaleness = priceMaxStaleness;
        emit PriceMaxStalenessChanged(priceMaxStaleness);
    }

    /**
     * @dev Verifies an array of two encoded Chainlink Data Streams reports.
     * @param signedReports An array of exactly two encoded Chainlink Data Streams reports that need to be verified.
     * @notice This function is specifically designed to handle and validate a pair of Chainlink Data Streams reports.
     */
    function _verifyDataStreamReports(bytes[] memory signedReports) private {
        VerifierProxy verifierProxy = VerifierProxy(s_verifierProxy);
        (, bytes memory report0Data) = abi.decode(signedReports[0], (bytes32[3], bytes));
        (, bytes memory report1Data) = abi.decode(signedReports[1], (bytes32[3], bytes));
        FeeManager feeManager = FeeManager(address(verifierProxy.s_feeManager()));
        (Common.Asset memory fee0,,) = feeManager.getFeeAndReward(address(this), report0Data, i_linkToken);
        (Common.Asset memory fee1,,) = feeManager.getFeeAndReward(address(this), report1Data, i_linkToken);
        IERC20(i_linkToken).approve(address(feeManager.i_rewardManager()), fee0.amount + fee1.amount);
        verifierProxy.verifyBulk(signedReports, abi.encode(i_linkToken));
    }

    /////////////////////////////
    // Private View Functions  //
    /////////////////////////////

    /**
     * @dev Calculates the necessary trade information for rebalancing a given self-balancing pool based on the prices of token0 and token1.
     * @param price0 The price of token0 in USD.
     * @param price1 The price of token1 in USD.
     * @param reserveIn The self-balancing pool reserve of token0.
     * @param reserveOut The self-balancing pool reserve of token1.
     * @param token0Decimals The number of decimals of token0.
     * @param token1Decimals The number of decimals of token1.
     * @return tradeInfo A struct containing the information for the rebalancing trade, including amounts to trade in and out.
     * @notice This function performs a series of calculations to determine how much of each token should be traded to achieve rebalancing.
     *         It takes into account the current reserves, prices, and decimal precision of the tokens.
     */
    function _computeRebalancingTrade(
        uint256 price0,
        uint256 price1,
        uint256 reserveIn,
        uint256 reserveOut,
        uint8 token0Decimals,
        uint8 token1Decimals
    ) private pure returns (RebalancingInfo memory tradeInfo) {
        (uint256 rateTokenIn, uint256 rateTokenOut) = price0 < price1
            ? (10 ** token0Decimals, FullMath.mulDiv(price0, 10 ** token1Decimals, price1))
            : (FullMath.mulDiv(price1, 10 ** token0Decimals, price0), 10 ** token1Decimals);
        tradeInfo.zeroToOne = FullMath.mulDiv(reserveIn, rateTokenOut, reserveOut) < rateTokenIn;
        if (!tradeInfo.zeroToOne) {
            (reserveIn, reserveOut, rateTokenIn, rateTokenOut) = (reserveOut, reserveIn, rateTokenOut, rateTokenIn);
        }
        uint256 leftSide = Babylonian.sqrt(
            FullMath.mulDiv(reserveIn * reserveOut, rateTokenIn * FL_FEE_DENOMINATOR, rateTokenOut * FL_FEE_NUMERATOR)
        );
        uint256 rightSide = reserveIn * FL_FEE_DENOMINATOR / FL_FEE_NUMERATOR;
        if (leftSide <= rightSide || reserveIn == 0 || reserveOut == 0) return tradeInfo;
        tradeInfo.amountIn = leftSide - rightSide;
        uint256 amountInWithFee = tradeInfo.amountIn * FL_FEE_NUMERATOR;
        tradeInfo.amountOut = amountInWithFee * reserveOut / ((reserveIn * FL_FEE_DENOMINATOR) + amountInWithFee);
    }

    /**
     * @dev Identifies the best route for a swap operation based on the input token, output token, and input amount.
     *      This function iterates through a list of available dex adapters to find the one offering the best output amount for the swap.
     * @param tokenIn The address of the input token for the swap.
     * @param tokenOut The address of the output token from the swap.
     * @param amountIn The amount of the input token for the swap.
     * @return maxOutput The maximum output amount for the output token that can be obtained from the swap.
     * @return adapterIndex The index of the dex adapter in the adapters array where the swap will yield the best output.
     * @return extraArgs Adapter specific encoded extra arguments, used for providing additional instructions or data required by the specific DEX adapter.
     */
    function _findBestRoute(address tokenIn, address tokenOut, uint256 amountIn)
        private
        view
        returns (uint256 maxOutput, uint256 adapterIndex, bytes memory extraArgs)
    {
        uint256 adaptersLen = s_adapters.length;
        uint256 tempOutput;
        bytes memory tempExtraArgs;
        for (uint256 i; i < adaptersLen;) {
            (tempOutput, tempExtraArgs) = s_adapters[i].getMaxOutput(tokenIn, tokenOut, amountIn);
            if (tempOutput > maxOutput) {
                adapterIndex = i;
                maxOutput = tempOutput;
                extraArgs = tempExtraArgs;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Determines whether a rebalancing trade is necessary for a given self-balancing pool based on current prices and configuration.
     * @param selfBalancingPool The address of the self-balancing pool under consideration.
     * @param priceTokenIn The current price of the input token.
     * @param priceTokenOut The current price of the output token.
     * @param jobConfig Configuration parameters for the Arbiter job, including token decimals and minimum profit threshold.
     * @return rebalancingNeeded A boolean indicating whether a rebalancing trade is necessary based on the profit potential and pool conditions.
     * @return arbiterCall An ArbiterCall struct containing the details of the rebalancing trade if one is needed.
     * @notice This function evaluates whether a rebalancing operation is profitable and necessary. It considers the current token prices, the best pool for the trade, and the configured minimum profit threshold.
     *         If the conditions are met for a profitable trade, it returns true for 'rebalancingNeeded' along with the 'arbiterCall' data necessary to perform the rebalancing operation.
     */
    function _isRebalancingNeeded(
        address selfBalancingPool,
        uint256 priceTokenIn,
        uint256 priceTokenOut,
        ArbiterJobConfig memory jobConfig
    ) private view returns (bool rebalancingNeeded, ArbiterCall memory arbiterCall) {
        (uint256 reserveIn, uint256 reserveOut,) = IFlashLiquidityPair(selfBalancingPool).getReserves();
        RebalancingInfo memory rebalancing = _computeRebalancingTrade(
            priceTokenIn, priceTokenOut, reserveIn, reserveOut, jobConfig.tokenInDecimals, jobConfig.tokenOutDecimals
        );
        if (!rebalancing.zeroToOne) {
            (jobConfig.tokenIn, jobConfig.tokenOut, priceTokenIn, jobConfig.tokenInDecimals) =
                (jobConfig.tokenOut, jobConfig.tokenIn, priceTokenOut, jobConfig.tokenOutDecimals);
        }
        if (rebalancing.amountIn == 0 || rebalancing.amountOut == 0) return (false, arbiterCall);
        (uint256 maxOutput, uint256 adapterIndex, bytes memory extraArgs) =
            _findBestRoute(jobConfig.tokenOut, jobConfig.tokenIn, rebalancing.amountOut);
        if (maxOutput > rebalancing.amountIn) {
            uint256 profitTrigger = rebalancing.zeroToOne ? reserveIn : reserveOut;
            profitTrigger = profitTrigger / jobConfig.reserveToTriggerProfit;
            if (maxOutput - rebalancing.amountIn >= profitTrigger) {
                rebalancingNeeded = true;
                arbiterCall = ArbiterCall({
                    selfBalancingPool: selfBalancingPool,
                    amountIn: rebalancing.amountIn,
                    amountOut: rebalancing.amountOut,
                    adapterIndex: adapterIndex,
                    extraArgs: extraArgs,
                    zeroToOne: rebalancing.zeroToOne
                });
            }
        }
    }

    /**
     * @dev Retrieves the latest price for a given token from its assigned Chainlink data feed, ensuring the price data is within an acceptable staleness threshold.
     * @param token The address of the token for which the price is to be fetched.
     * @param priceMaxStaleness The maximum acceptable staleness for price data in seconds. If the latest price data is older than this threshold, the function will revert.
     * @return The latest price of the token as a uint256.
     * @notice The function first checks if the token has an associated data feed. If not, it reverts with 'Arbiter__DataFeedNotSet'.
     * @notice It then fetches the latest price and its update timestamp. If the price is invalid (non-positive) or too stale (older than 'priceMaxStaleness'), the function reverts with 'Arbiter__InvalidPrice' or 'Arbiter__StalenessTooHigh', respectively.
     */
    function _getPriceFromDataFeed(address token, uint256 priceMaxStaleness) private view returns (uint256) {
        AggregatorV3Interface priceFeed = s_dataFeeds[token];
        if (address(priceFeed) == address(0)) revert Arbiter__DataFeedNotSet();
        (, int256 price,, uint256 priceUpdatedAt,) = priceFeed.latestRoundData();
        if (price <= int256(0)) revert Arbiter__InvalidPrice();
        if (block.timestamp - priceUpdatedAt > priceMaxStaleness) revert Arbiter__StalenessTooHigh();
        return uint256(price);
    }

    /////////////////////////////
    // External View Functions //
    /////////////////////////////

    /**
     * @inheritdoc AutomationCompatibleInterface
     * @dev Checks if an upkeep is needed for a given self-balancing pool. This function is part of the Chainlink Automation integration.
     * @param checkData Encoded data specifying the self-balancing pool to check for potential rebalancing.
     * @return upkeepNeeded A boolean indicating whether rebalancing is needed for the specified pool.
     * @return performData Data to be used for the rebalancing operation if upkeep is needed.
     *
     * In the function:
     * 1. Decodes `checkData` to extract the self-balancing pool address.
     * 2. Fetches the job configuration for the specified pool.
     * 3. Checks if data streams are set for the pool's tokens. If not, it fetches prices from data feeds and determines if rebalancing is required.
     * 4. If data streams are set, it reverts with StreamsLookup error and Automation network will use this revert to trigger fetching of the specified reports.
     *
     * @notice This function determines the need for upkeep by comparing token prices and the configured job parameters.
     */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address selfBalancingPool = abi.decode(checkData, (address));
        ArbiterJobConfig memory jobConfig = s_jobConfig[selfBalancingPool];
        string[] memory feedIDs = new string[](2);
        feedIDs[0] = s_dataStreams[jobConfig.tokenIn];
        feedIDs[1] = s_dataStreams[jobConfig.tokenOut];
        if (bytes(feedIDs[0]).length == 0 || bytes(feedIDs[1]).length == 0) {
            uint256 maxPriceStaleness = s_priceMaxStaleness;
            uint256 priceTokenIn = _getPriceFromDataFeed(jobConfig.tokenIn, maxPriceStaleness);
            uint256 priceTokenOut = _getPriceFromDataFeed(jobConfig.tokenOut, maxPriceStaleness);
            ArbiterCall memory arbiterCall;
            (upkeepNeeded, arbiterCall) =
                _isRebalancingNeeded(selfBalancingPool, priceTokenIn, priceTokenOut, jobConfig);
            performData = abi.encode(new bytes[](0), arbiterCall);
        } else {
            revert StreamsLookup("feedIDs", feedIDs, "timestamp", block.timestamp, checkData);
        }
    }

    /**
     * @inheritdoc StreamsLookupCompatibleInterface
     * @dev Checks if rebalancing is needed for a self-balancing pool based on Chainlink Data Streams reports. Implements the StreamsLookupCompatibleInterface.
     * @param values An array of encoded Chainlink Data Streams reports.
     * @param extraData Encoded extra data, typically containing the address of the self-balancing pool.
     * @return upkeepNeeded A boolean indicating whether a rebalancing operation is needed.
     * @return performData Data to be used for the rebalancing operation if upkeep is needed.
     *
     * In the function:
     * 1. Decodes `extraData` to extract the self-balancing pool address.
     * 2. Decodes the first two elements of `values` to get the reports for tokenIn and tokenOut.
     * 3. Checks for valid prices in the reports. If any price is non-positive, it reverts with 'Arbiter__InvalidPrice'.
     * 4. Retrieves the job configuration for the specified pool.
     * 5. Extract the prices from the reports and checks if rebalancing is needed based on these prices and the job configuration.
     *
     * @notice This function is triggered by Chainlink Data Streams and is used to automate the rebalancing of pools based on external data.
     * @notice It ensures that the pool is rebalanced only when the conditions defined in the job configuration are met.
     */
    function checkCallback(bytes[] memory values, bytes memory extraData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address selfBalancingPool = abi.decode(extraData, (address));
        (, bytes memory reportDataTokenIn) = abi.decode(values[0], (bytes32[3], bytes));
        (, bytes memory reportDataTokenOut) = abi.decode(values[1], (bytes32[3], bytes));
        PremiumReport memory reportTokenIn = abi.decode(reportDataTokenIn, (PremiumReport));
        PremiumReport memory reportTokenOut = abi.decode(reportDataTokenOut, (PremiumReport));
        if (reportTokenIn.price <= int192(0) || reportTokenOut.price <= int192(0)) {
            revert Arbiter__InvalidPrice();
        }
        ArbiterCall memory arbiterCall;
        (upkeepNeeded, arbiterCall) = _isRebalancingNeeded(
            selfBalancingPool,
            uint192(reportTokenIn.price),
            uint192(reportTokenOut.price),
            s_jobConfig[selfBalancingPool]
        );
        performData = abi.encode(values, arbiterCall);
    }

    /**
     * @inheritdoc StreamsLookupCompatibleInterface
     * @dev This function is triggered by Chainlink Data Streams if the reports retrieval process fail, fallback to Chainlink Data Feeds to checks if rebalancing is needed.
     * @param extraData Encoded extra data, containing the address of the self-balancing pool.
     * @return upkeepNeeded A boolean indicating whether a rebalancing operation is needed.
     * @return performData Data to be used for the rebalancing operation if upkeep is needed.
     */
    function checkErrorHandler(uint256, bytes memory extraData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address selfBalancingPool = abi.decode(extraData, (address));
        ArbiterJobConfig memory jobConfig = s_jobConfig[selfBalancingPool];
        uint256 maxPriceStaleness = s_priceMaxStaleness;
        uint256 priceTokenIn = _getPriceFromDataFeed(jobConfig.tokenIn, maxPriceStaleness);
        uint256 priceTokenOut = _getPriceFromDataFeed(jobConfig.tokenOut, maxPriceStaleness);
        ArbiterCall memory arbiterCall;
        (upkeepNeeded, arbiterCall) = _isRebalancingNeeded(selfBalancingPool, priceTokenIn, priceTokenOut, jobConfig);
        performData = abi.encode(new bytes[](0), arbiterCall);
    }

    /// @inheritdoc IArbiter
    function getVerifierProxy() external view returns (address) {
        return address(s_verifierProxy);
    }

    /// @inheritdoc IArbiter
    function getPriceMaxStaleness() external view returns (uint256) {
        return s_priceMaxStaleness;
    }

    /// @inheritdoc IArbiter
    function getJobConfig(address selfBalancingPool)
        external
        view
        returns (address, uint96, address, uint96, address, uint8, address, uint8)
    {
        ArbiterJobConfig memory jobConfig = s_jobConfig[selfBalancingPool];
        return (
            jobConfig.rewardVault,
            jobConfig.reserveToMinProfit,
            jobConfig.automationForwarder,
            jobConfig.reserveToTriggerProfit,
            jobConfig.tokenIn,
            jobConfig.tokenInDecimals,
            jobConfig.tokenOut,
            jobConfig.tokenOutDecimals
        );
    }

    /// @inheritdoc IArbiter
    function getDataFeed(address token) external view returns (address) {
        return address(s_dataFeeds[token]);
    }

    /// @inheritdoc IArbiter
    function getDataStream(address token) external view returns (string memory) {
        return s_dataStreams[token];
    }

    /// @inheritdoc IArbiter
    function getDexAdapter(uint256 adapterIndex) external view returns (address) {
        return address(s_adapters[adapterIndex]);
    }

    /// @inheritdoc IArbiter
    function allAdaptersLength() external view returns (uint256) {
        return s_adapters.length;
    }
}
