//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AutomationCompatible} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3PoolActions} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import {IArbiter} from "./interfaces/IArbiter.sol";
import {IFlashLiquidityPair} from "./interfaces/IFlashLiquidityPair.sol";
import {IUniswapV3Router} from "./interfaces/IUniswapV3Router.sol";
import {IUniswapV3Quoter} from "./interfaces/IUniswapV3Quoter.sol";
import {IAlgebraRouter} from "./interfaces/IAlgebraRouter.sol";
import {IAlgebraQuoter} from "./interfaces/IAlgebraQuoter.sol";
import {IKyberswapRouter} from "./interfaces/IKyberswapRouter.sol";
import {BastionConnector} from "./types/BastionConnector.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {Babylonian} from "./libraries/Babylonian.sol";

contract Arbiter is IArbiter, BastionConnector, AutomationCompatible {
    using SafeERC20 for IERC20;

    address private permissionedPairAddress = address(1);
    uint256 public maxStaleness;
    uint24 private constant FL_FEE = 9994;
    ArbiterJob[] private jobs;
    mapping(address => ArbiterJobConfig) internal jobsConfig;
    mapping(address => AggregatorV3Interface) internal priceFeeds;
    mapping(address => address) internal quoters;
    mapping(address => address) internal routers;

    error ZeroProfit();
    error RouterNotSet();
    error QuoterNotSet();
    error AdjFactorTooLow();
    error UnknownPoolType();
    error InsufficentInput();
    error InsufficentLiquidity();
    error NotPermissioned();
    error NotProfitable();
    error InvalidPool();
    error InvalidPrice();
    error PriceFeedNotSet();
    error ArbiterIsNotManager();
    error StalenessToHigh();

    event ProfitsDistributed(
        address indexed _farm,
        address indexed _rewardToken,
        uint256 indexed _amount
    );
    event StalenessChanged(uint256 indexed newStaleness);
    event NewJob(address indexed _farm, address indexed _flPool);
    event JobParamsChanged(
        uint32 indexed _jobIndex,
        uint32 indexed _adjFactor,
        uint128 indexed _minProfitInUsd
    );
    event JobRemoved(uint256 indexed _jobIndex);
    event PoolAddedToJob(
        uint256 indexed jobIndex,
        address indexed poolAddr,
        PoolType indexed poolType,
        uint24 poolFee
    );
    event PoolRemovedFromJob(uint256 indexed jobIndex, uint256 indexed indexPool);

    enum PoolType {
        UniswapV2,
        UniswapV3,
        Algebra,
        KyberSwap
    }
    struct Pool {
        address poolAddr;
        PoolType poolType;
        uint24 poolFee;
    }
    struct ArbiterJob {
        address flFarm;
        address flPool;
        address token0;
        address token1;
        bool token0IsRewardToken;
    }
    struct ArbiterJobConfig {
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint32 adjFactor;
        uint32 reserveToProfitRatio;
        Pool[] targetPools;
    }
    struct ArbiterCall {
        uint32 jobIndex;
        uint112 amountInFlash;
        uint112 amountOutFlash;
        uint32 bestPoolIndex;
        uint112 amountOutExt;
        bool tokenInIsRewardToken;
        bool zeroToOne;
    }
    struct CallbackData {
        address flPool;
        Pool targetPool;
        address token0;
        address token1;
        uint112 amountDebt;
        uint112 amountOutExt;
        bool zeroToOne;
    }

    constructor(
        address _governor,
        address _bastion,
        uint256 _transferGovernanceDelay,
        uint256 _maxStaleness
    ) BastionConnector(_governor, _bastion, _transferGovernanceDelay) {
        maxStaleness = _maxStaleness;
    }

    function getJob(
        uint256 _index
    )
        external
        view
        returns (
            address _flFarm,
            address _flPool,
            address _token0,
            address _token1,
            bool _token0IsRewardToken
        )
    {
        ArbiterJob memory _job = jobs[_index];
        _flFarm = _job.flFarm;
        _flPool = _job.flPool;
        _token0 = _job.token0;
        _token1 = _job.token1;
        _token0IsRewardToken = _job.token0IsRewardToken;
    }

    function getJobConfig(
        uint256 _index
    )
        external
        view
        returns (
            uint8 _token0Decimals,
            uint8 _token1Decimals,
            uint32 _adjFactor,
            uint32 _reserveToProfitRatio,
            address[] memory _targetPools,
            uint256[] memory _poolTypes,
            uint24[] memory _poolFees
        )
    {
        ArbiterJobConfig memory _config = jobsConfig[jobs[_index].flPool];
        uint256 _poolsLength = _config.targetPools.length;
        _token0Decimals = _config.token0Decimals;
        _token1Decimals = _config.token1Decimals;
        _adjFactor = _config.adjFactor;
        _reserveToProfitRatio = _config.reserveToProfitRatio;
        _targetPools = new address[](_poolsLength);
        _poolTypes = new uint256[](_poolsLength);
        _poolFees = new uint24[](_poolsLength);
        for (uint256 i = 0; i < _poolsLength; ) {
            _targetPools[i] = _config.targetPools[i].poolAddr;
            _poolTypes[i] = uint256(_config.targetPools[i].poolType);
            _poolFees[i] = _config.targetPools[i].poolFee;
            unchecked {
                i++;
            }
        }
    }

    function setMaxStaleness(uint256 _maxStaleness) external onlyGovernor {
        maxStaleness = _maxStaleness;
        emit StalenessChanged(_maxStaleness);
    }

    function setPriceFeeds(
        address[] calldata _tokens,
        address[] calldata _priceFeeds
    ) external onlyGovernor {
        for (uint256 i = 0; i < _tokens.length; ) {
            priceFeeds[_tokens[i]] = AggregatorV3Interface(_priceFeeds[i]);
            unchecked {
                i++;
            }
        }
    }

    function setQuoters(
        address[] calldata _pools,
        address[] calldata _quoters
    ) external onlyGovernor {
        for (uint256 i = 0; i < _pools.length; ) {
            quoters[_pools[i]] = _quoters[i];
            unchecked {
                i++;
            }
        }
    }

    function setRouters(
        address[] calldata _pools,
        address[] calldata _routers
    ) external onlyGovernor {
        for (uint256 i = 0; i < _pools.length; ) {
            routers[_pools[i]] = _routers[i];
            unchecked {
                i++;
            }
        }
    }

    function pushArbiterJob(
        address _farm,
        address _flashPool,
        uint32 _adjFactor,
        uint32 _reserveToProfitRatio,
        bool _token0IsRewardToken,
        address[] calldata _targetPools,
        uint256[] calldata _poolTypes,
        uint24[] calldata _poolFees
    ) external onlyGovernor {
        (address _token0, address _token1) = (
            IFlashLiquidityPair(_flashPool).token0(),
            IFlashLiquidityPair(_flashPool).token1()
        );
        if (_token0 == address(0) || _token1 == address(1)) {
            revert InvalidPool();
        }
        if (IFlashLiquidityPair(_flashPool).manager() != address(this)) {
            revert ArbiterIsNotManager();
        }
        if (
            address(priceFeeds[_token0]) == address(0) || address(priceFeeds[_token1]) == address(0)
        ) {
            revert PriceFeedNotSet();
        }
        jobs.push(
            ArbiterJob({
                flFarm: _farm,
                flPool: _flashPool,
                token0: _token0,
                token1: _token1,
                token0IsRewardToken: _token0IsRewardToken
            })
        );
        ArbiterJobConfig storage config = jobsConfig[_flashPool];
        if (config.token0Decimals == 0) {
            config.token0Decimals = ERC20(_token0).decimals();
        }
        if (config.token1Decimals == 0) {
            config.token1Decimals = ERC20(_token1).decimals();
        }
        config.adjFactor = _adjFactor;
        config.reserveToProfitRatio = _reserveToProfitRatio;
        for (uint256 i = 0; i < _targetPools.length; ) {
            if (PoolType(_poolTypes[i]) != PoolType.UniswapV2) {
                if (routers[_targetPools[i]] == address(0)) {
                    revert RouterNotSet();
                }
                if (quoters[_targetPools[i]] == address(0)) {
                    revert QuoterNotSet();
                }
            }
            config.targetPools.push(
                Pool({
                    poolAddr: _targetPools[i],
                    poolType: PoolType(_poolTypes[i]),
                    poolFee: _poolFees[i]
                })
            );
            unchecked {
                i++;
            }
        }
        emit NewJob(_farm, _flashPool);
    }

    function setArbiterJobConfig(
        uint32 _jobIndex,
        uint32 _adjFactor,
        uint32 _reserveToProfitRatio
    ) external onlyGovernor {
        if (_reserveToProfitRatio == 0) revert ZeroProfit();
        if (_adjFactor < 10) revert AdjFactorTooLow();
        ArbiterJob memory job = jobs[_jobIndex];
        ArbiterJobConfig storage config = jobsConfig[job.flPool];
        config.adjFactor = _adjFactor;
        config.reserveToProfitRatio = _reserveToProfitRatio;
        emit JobParamsChanged(_jobIndex, _adjFactor, _reserveToProfitRatio);
    }

    function setConfigTokensDecimals(
        address _flPool,
        uint8 _token0Decimals,
        uint8 _token1Decimals
    ) external onlyGovernor {
        ArbiterJobConfig storage config = jobsConfig[_flPool];
        config.token0Decimals = _token0Decimals;
        config.token1Decimals = _token1Decimals;
    }

    function removeArbiterJob(uint256 jobIndex) external onlyGovernor {
        ArbiterJob storage job = jobs[jobIndex];
        ArbiterJobConfig storage config = jobsConfig[job.flPool];
        uint256 jobLastIndex = jobs.length - 1;
        if (jobIndex < jobLastIndex) {
            job = jobs[jobLastIndex];
        }
        for (uint256 i = config.targetPools.length; i > 0; ) {
            unchecked {
                i--;
            }
            Pool memory _pool = config.targetPools[i];
            delete routers[_pool.poolAddr];
            delete quoters[_pool.poolAddr];
            config.targetPools.pop();
        }
        jobs.pop();
        emit JobRemoved(jobIndex);
    }

    function pushPoolToJob(
        uint256 jobIndex,
        address _pool,
        uint256 _type,
        uint24 _fee
    ) external onlyGovernor {
        PoolType _poolType = PoolType(_type);
        if (routers[_pool] == address(0) && _poolType != PoolType.UniswapV2) {
            revert RouterNotSet();
        }
        if (quoters[_pool] == address(0) && _poolType != PoolType.UniswapV2) {
            revert QuoterNotSet();
        }
        Pool storage pool = jobsConfig[jobs[jobIndex].flPool].targetPools.push();
        pool.poolAddr = _pool;
        pool.poolType = _poolType;
        pool.poolFee = _fee;
        emit PoolAddedToJob(jobIndex, _pool, _poolType, _fee);
    }

    function removePoolFromJob(uint256 jobIndex, uint8 poolIndex) external onlyGovernor {
        ArbiterJob memory _job = jobs[jobIndex];
        ArbiterJobConfig storage _config = jobsConfig[_job.flPool];
        uint256 poolsLastIndex = _config.targetPools.length - 1;
        Pool storage _pool = _config.targetPools[poolIndex];
        delete routers[_pool.poolAddr];
        delete quoters[_pool.poolAddr];
        if (poolIndex < poolsLastIndex) {
            _pool = _config.targetPools[poolsLastIndex];
        }
        _config.targetPools.pop();
        emit PoolRemovedFromJob(jobIndex, poolIndex);
    }

    function computeProfitMaximizingTrade(
        address _flashPool,
        uint32 _reserveToProfitRatio,
        uint256 _price0,
        uint256 _price1,
        uint8 _token0Decimals,
        uint8 _token1Decimals
    )
        internal
        view
        returns (bool _zeroToOne, uint256 _amountIn, uint256 _amountOut, uint256 _minProfit)
    {
        (uint256 _reserve0, uint256 _reserve1, ) = IFlashLiquidityPair(_flashPool).getReserves();
        (uint256 _rate0, uint256 _rate1) = (
            10 ** uint256(_token0Decimals),
            (_price0 * (10 ** uint256(_token1Decimals))) / _price1
        );
        _zeroToOne = FullMath.mulDiv(_reserve0, _rate1, _reserve1) < _rate0;
        uint256 _leftSide = Babylonian.sqrt(
            FullMath.mulDiv(
                _reserve0 * _reserve1 * 10000,
                _zeroToOne ? _rate0 : _rate1,
                (_zeroToOne ? _rate1 : _rate0) * FL_FEE
            )
        );
        uint256 _rightSide = (_zeroToOne ? _reserve0 * 10000 : _reserve1 * 10000) / FL_FEE;
        if (_leftSide < _rightSide) return (false, 0, 0, 0);
        _minProfit = (_zeroToOne ? _reserve0 : _reserve1) / _reserveToProfitRatio;
        _amountIn = uint112(_leftSide - _rightSide);
        (_reserve0, _reserve1) = _zeroToOne ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        _amountOut = uint112(getAmountOutUniswapV2(_amountIn, _reserve0, _reserve1, FL_FEE));
    }

    function getAmountInUniswapV2(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 poolFee
    ) internal pure returns (uint256 amountIn) {
        if (amountOut == 0) revert InsufficentInput();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficentLiquidity();
        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = reserveOut - amountOut * poolFee;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountOutUniswapV2(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 poolFee
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficentInput();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficentLiquidity();
        uint256 amountInWithFee = amountIn * poolFee;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 10000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountOut(
        uint256 amountIn,
        bool zeroToOne,
        address token0,
        address token1,
        Pool memory pool
    ) internal view returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = zeroToOne ? (token0, token1) : (token1, token0);
        if (pool.poolType == PoolType.UniswapV2) {
            (uint256 reserve0, uint256 reserve1, ) = IFlashLiquidityPair(pool.poolAddr)
                .getReserves();
            (reserve0, reserve1) = zeroToOne ? (reserve0, reserve1) : (reserve1, reserve0);
            amountOut = getAmountOutUniswapV2(amountIn, reserve0, reserve1, pool.poolFee);
        } else if (pool.poolType == PoolType.UniswapV3 || pool.poolType == PoolType.KyberSwap) {
            IUniswapV3Quoter.QuoteExactInputSingleParams memory params = IUniswapV3Quoter
                .QuoteExactInputSingleParams(tokenIn, tokenOut, amountIn, pool.poolFee, 0);
            amountOut = IUniswapV3Quoter(quoters[pool.poolAddr]).quoteExactInputSingle(params);
        } else if (pool.poolType == PoolType.Algebra) {
            IAlgebraQuoter.QuoteExactInputSingleParams memory params = IAlgebraQuoter
                .QuoteExactInputSingleParams(tokenIn, tokenOut, amountIn, 0);
            amountOut = IAlgebraQuoter(quoters[pool.poolAddr]).quoteExactInputSingle(params);
        }
    }

    function flashLiquidityCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) public {
        if (msg.sender != permissionedPairAddress) revert NotPermissioned();
        if (sender != address(this)) revert NotAuthorized();
        CallbackData memory info = abi.decode(data, (CallbackData));
        (address tokenIn, address tokenOut) = info.zeroToOne
            ? (info.token0, info.token1)
            : (info.token1, info.token0);
        if (info.targetPool.poolType == PoolType.UniswapV2) {
            (uint256 amount0Out, uint256 amount1Out) = info.zeroToOne
                ? (uint112(0), info.amountOutExt)
                : (info.amountOutExt, uint112(0));
            IERC20(tokenIn).safeTransfer(info.targetPool.poolAddr, amount0 > 0 ? amount0 : amount1);
            IFlashLiquidityPair(info.targetPool.poolAddr).swap(
                amount0Out,
                amount1Out,
                address(this),
                new bytes(0)
            );
        } else if (info.targetPool.poolType == PoolType.UniswapV3) {
            address _router = routers[info.targetPool.poolAddr];
            IERC20(tokenIn).approve(_router, amount0 > 0 ? amount0 : amount1);
            IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
                .ExactInputSingleParams(
                    tokenIn,
                    tokenOut,
                    info.targetPool.poolFee,
                    address(this),
                    block.timestamp,
                    amount0 > 0 ? amount0 : amount1,
                    info.amountOutExt,
                    0
                );
            IUniswapV3Router(_router).exactInputSingle(params);
        } else if (info.targetPool.poolType == PoolType.Algebra) {
            address _router = routers[info.targetPool.poolAddr];
            IERC20(tokenIn).approve(_router, amount0 > 0 ? amount0 : amount1);
            IAlgebraRouter.ExactInputSingleParams memory params = IAlgebraRouter
                .ExactInputSingleParams(
                    tokenIn,
                    tokenOut,
                    address(this),
                    block.timestamp,
                    amount0 > 0 ? amount0 : amount1,
                    info.amountOutExt,
                    0
                );
            IAlgebraRouter(_router).exactInputSingle(params);
        } else if (info.targetPool.poolType == PoolType.KyberSwap) {
            address _router = routers[info.targetPool.poolAddr];
            IERC20(tokenIn).approve(_router, amount0 > 0 ? amount0 : amount1);
            IKyberswapRouter.ExactInputSingleParams memory params = IKyberswapRouter
                .ExactInputSingleParams(
                    tokenIn,
                    tokenOut,
                    info.targetPool.poolFee,
                    address(this),
                    block.timestamp,
                    amount0 > 0 ? amount0 : amount1,
                    info.amountOutExt,
                    0
                );
            IKyberswapRouter(_router).swapExactInputSingle(params);
        } else {
            revert UnknownPoolType();
        }
        IERC20(tokenOut).safeTransfer(info.flPool, info.amountDebt);
    }

    function _withdraw(address _farm, uint256 _balance, IERC20 _token) internal {
        if (_balance > 0) {
            uint256 fee = _balance / 50;
            _balance = _balance - fee;
            _token.safeTransfer(_farm, _balance);
            _token.safeTransfer(bastion, fee);
            emit ProfitsDistributed(_farm, address(_token), _balance);
        }
    }

    function _findBestPool(
        bool zeroToOne,
        uint256 amountInFlash,
        uint256 amountOutFlash,
        ArbiterJob memory job,
        ArbiterJobConfig memory config
    ) internal view returns (uint32 bestPoolIndex, uint256 bestProfit, uint256 amountOutExt) {
        uint256 tempProfit;
        uint256 amountOutExtTemp;
        for (uint32 i = 0; i < config.targetPools.length; ) {
            amountOutExtTemp = getAmountOut(
                amountOutFlash,
                !zeroToOne,
                job.token0,
                job.token1,
                config.targetPools[i]
            );
            tempProfit = amountOutExtTemp > amountInFlash ? amountOutExtTemp - amountInFlash : 0;
            if (tempProfit > bestProfit) {
                bestPoolIndex = i;
                bestProfit = tempProfit;
                amountOutExt = amountOutExtTemp;
            }
            unchecked {
                i++;
            }
        }
    }

    function _getPrices(address _token0, address _token1) internal view returns (uint256, uint256) {
        uint256 _maxStaleness = maxStaleness;
        (, int256 _price0, , uint256 _price0UpdatedAt, ) = priceFeeds[_token0].latestRoundData();
        (, int256 _price1, , uint256 _price1UpdateAt, ) = priceFeeds[_token1].latestRoundData();
        if (_price0 <= int256(0) || _price1 <= int256(0)) {
            revert InvalidPrice();
        }
        if (block.timestamp - _price0UpdatedAt > _maxStaleness) {
            revert StalenessToHigh();
        }
        if (block.timestamp - _price1UpdateAt > _maxStaleness) {
            revert StalenessToHigh();
        }
        return (uint256(_price0), uint256(_price1));
    }

    function checkUpkeep(
        bytes calldata checkData
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 _jobIndex = abi.decode(checkData, (uint256));
        ArbiterJob memory job = jobs[_jobIndex];
        ArbiterJobConfig memory config = jobsConfig[job.flPool];
        (uint256 _price0, uint256 _price1) = _getPrices(job.token0, job.token1);
        (
            bool _zeroToOne,
            uint256 _amountInFlash,
            uint256 _amountOutFlash,
            uint256 _minProfit
        ) = computeProfitMaximizingTrade(
                job.flPool,
                config.reserveToProfitRatio,
                _price0,
                _price1,
                config.token0Decimals,
                config.token1Decimals
            );
        if (_amountInFlash == 0) return (false, new bytes(0));
        (uint32 _bestPoolIndex, uint256 _bestProfit, uint256 _amountOutExt) = _findBestPool(
            _zeroToOne,
            _amountInFlash,
            _amountOutFlash,
            job,
            config
        );
        _bestProfit -= _bestProfit / config.adjFactor;
        if (_bestProfit > _minProfit) {
            ArbiterCall memory _arbiterCall = ArbiterCall(
                uint32(_jobIndex),
                uint112(_amountInFlash),
                uint112(_amountOutFlash),
                _bestPoolIndex,
                uint112(_amountOutExt),
                job.token0IsRewardToken == _zeroToOne,
                _zeroToOne
            );
            upkeepNeeded = true;
            performData = abi.encode(_arbiterCall);
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        ArbiterCall memory _call = abi.decode(performData, (ArbiterCall));
        ArbiterJob memory _job = jobs[_call.jobIndex];
        CallbackData memory _callbackData = CallbackData(
            _job.flPool,
            jobsConfig[_job.flPool].targetPools[_call.bestPoolIndex],
            _job.token0,
            _job.token1,
            _call.amountInFlash,
            _call.amountOutExt,
            !_call.zeroToOne
        );
        permissionedPairAddress = _job.flPool;
        (IERC20 _tokenIn, IERC20 _tokenOut) = _call.zeroToOne
            ? (IERC20(_job.token0), IERC20(_job.token1))
            : (IERC20(_job.token1), IERC20(_job.token0));
        (uint256 _amount0Flash, uint256 _amount1Flash) = _call.zeroToOne
            ? (uint112(0), _call.amountOutFlash)
            : (_call.amountOutFlash, uint112(0));
        uint256 _balanceBefore = _tokenIn.balanceOf(address(this));
        IFlashLiquidityPair _flPool = IFlashLiquidityPair(_job.flPool);
        (uint256 _reserve0, uint256 _reserve1, ) = _flPool.getReserves();
        _flPool.swap(_amount0Flash, _amount1Flash, address(this), abi.encode(_callbackData));
        uint256 _profit = _tokenIn.balanceOf(address(this)) - _balanceBefore;
        if (
            _profit <
            (_call.zeroToOne ? _reserve0 : _reserve1) / jobsConfig[_job.flPool].reserveToProfitRatio
        ) {
            revert NotProfitable();
        }
        if (!_call.tokenInIsRewardToken) {
            uint256 _balance = _tokenIn.balanceOf(address(this));
            (_reserve0, _reserve1, ) = _flPool.getReserves();
            (_reserve0, _reserve1) = _call.zeroToOne
                ? (_reserve0, _reserve1)
                : (_reserve1, _reserve0);
            uint256 _amountOut = getAmountOutUniswapV2(_balance, _reserve0, _reserve1, FL_FEE);
            (_amount0Flash, _amount1Flash) = _call.zeroToOne
                ? (uint256(0), _amountOut)
                : (_amountOut, uint256(0));
            _tokenIn.safeTransfer(_job.flPool, _balance);
            _flPool.swap(_amount0Flash, _amount1Flash, address(this), new bytes(0));
            _profit = _tokenOut.balanceOf(address(this));
        }
        permissionedPairAddress = address(1);
        _withdraw(_job.flFarm, _profit, _call.tokenInIsRewardToken ? _tokenIn : _tokenOut);
    }
}
