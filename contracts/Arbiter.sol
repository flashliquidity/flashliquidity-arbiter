//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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
        uint256 amountInFlash;
        uint256 amountOutFlash;
        uint32 bestPoolIndex;
        bool tokenInIsRewardToken;
        bool zeroToOne;
    }
    struct CallbackData {
        address flPool;
        Pool targetPool;
        address token0;
        address token1;
        uint256 amountDebt;
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
            config.token0Decimals = IERC20Metadata(_token0).decimals();
        }
        if (config.token1Decimals == 0) {
            config.token1Decimals = IERC20Metadata(_token1).decimals();
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
        ArbiterJob memory _job = jobs[_jobIndex];
        ArbiterJobConfig storage config = jobsConfig[_job.flPool];
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

    function removeArbiterJob(uint256 _jobIndex) external onlyGovernor {
        ArbiterJob storage job = jobs[_jobIndex];
        ArbiterJobConfig storage config = jobsConfig[job.flPool];
        uint256 _jobLastIndex = jobs.length - 1;
        if (_jobIndex < _jobLastIndex) {
            job = jobs[_jobLastIndex];
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
        emit JobRemoved(_jobIndex);
    }

    function pushPoolToJob(
        uint256 _jobIndex,
        address _poolAddr,
        uint256 _poolType,
        uint24 _poolFee
    ) external onlyGovernor {
        PoolType poolType_ = PoolType(_poolType);
        if (routers[_poolAddr] == address(0) && poolType_ != PoolType.UniswapV2) {
            revert RouterNotSet();
        }
        if (quoters[_poolAddr] == address(0) && poolType_ != PoolType.UniswapV2) {
            revert QuoterNotSet();
        }
        Pool storage _pool = jobsConfig[jobs[_jobIndex].flPool].targetPools.push();
        _pool.poolAddr = _poolAddr;
        _pool.poolType = poolType_;
        _pool.poolFee = _poolFee;
        emit PoolAddedToJob(_jobIndex, _poolAddr, poolType_, _poolFee);
    }

    function removePoolFromJob(uint256 _jobIndex, uint8 _poolIndex) external onlyGovernor {
        ArbiterJob memory _job = jobs[_jobIndex];
        ArbiterJobConfig storage _config = jobsConfig[_job.flPool];
        uint256 _poolsLastIndex = _config.targetPools.length - 1;
        Pool storage _pool = _config.targetPools[_poolIndex];
        delete routers[_pool.poolAddr];
        delete quoters[_pool.poolAddr];
        if (_poolIndex < _poolsLastIndex) {
            _pool = _config.targetPools[_poolsLastIndex];
        }
        _config.targetPools.pop();
        emit PoolRemovedFromJob(_jobIndex, _poolIndex);
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

    function getAmountOutUniswapV2(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut,
        uint24 _poolFee
    ) internal pure returns (uint256 amountOut) {
        if (_amountIn == 0) {
            revert InsufficentInput();
        }
        if (_reserveIn == 0 || _reserveOut == 0){
            revert InsufficentLiquidity();
        }
        uint256 _amountInWithFee = _amountIn * _poolFee;
        uint256 _numerator = _amountInWithFee * _reserveOut;
        uint256 _denominator = (_reserveIn * 10000) + _amountInWithFee;
        amountOut = _numerator / _denominator;
    }

    function getAmountOut(
        uint256 _amountIn,
        bool _zeroToOne,
        address _token0,
        address _token1,
        Pool memory _pool
    ) internal view returns (uint256 amountOut) {
        (address _tokenIn, address _tokenOut) = _zeroToOne ? (_token0, _token1) : (_token1, _token0);
        if (_pool.poolType == PoolType.UniswapV2) {
            (uint256 _reserve0, uint256 _reserve1, ) = IFlashLiquidityPair(_pool.poolAddr)
                .getReserves();
            (_reserve0, _reserve1) = _zeroToOne ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            amountOut = getAmountOutUniswapV2(_amountIn, _reserve0, _reserve1, _pool.poolFee);
        } else if (_pool.poolType == PoolType.UniswapV3 || _pool.poolType == PoolType.KyberSwap) {
            IUniswapV3Quoter.QuoteExactInputSingleParams memory params = IUniswapV3Quoter
                .QuoteExactInputSingleParams(_tokenIn, _tokenOut, _amountIn, _pool.poolFee, 0);
            amountOut = IUniswapV3Quoter(quoters[_pool.poolAddr]).quoteExactInputSingle(params);
        } else if (_pool.poolType == PoolType.Algebra) {
            IAlgebraQuoter.QuoteExactInputSingleParams memory params = IAlgebraQuoter
                .QuoteExactInputSingleParams(_tokenIn, _tokenOut, _amountIn, 0);
            amountOut = IAlgebraQuoter(quoters[_pool.poolAddr]).quoteExactInputSingle(params);
        }
    }

    function flashLiquidityCall(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    ) public {
        if (msg.sender != permissionedPairAddress) {
            revert NotPermissioned();
        }
        if (_sender != address(this)) {
            revert NotAuthorized();
        }
        CallbackData memory _info = abi.decode(_data, (CallbackData));
        (address _tokenIn, address _tokenOut) = _info.zeroToOne
            ? (_info.token0, _info.token1)
            : (_info.token1, _info.token0);
        if (_info.targetPool.poolType == PoolType.UniswapV2) {
            uint256 _amount0Out = getAmountOut(
                _info.zeroToOne ? _amount0 : _amount1, 
                _info.zeroToOne, 
                _info.token0, 
                _info.token1, 
                _info.targetPool
            );
            uint256 _amount1Out;
            (_amount0Out, _amount1Out) = _info.zeroToOne
                ? (uint256(0), _amount0Out)
                : (_amount0Out, uint256(0));
            IERC20(_tokenIn).safeTransfer(
                _info.targetPool.poolAddr, 
                _info.zeroToOne ? _amount0 : _amount1
            );
            IFlashLiquidityPair(_info.targetPool.poolAddr).swap(
                _amount0Out,
                _amount1Out,
                address(this),
                new bytes(0)
            );
        } else if (_info.targetPool.poolType == PoolType.UniswapV3) {
            address _router = routers[_info.targetPool.poolAddr];
            IERC20(_tokenIn).approve(_router, _amount0 > 0 ? _amount0 : _amount1);
            IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
                .ExactInputSingleParams(
                    _tokenIn,
                    _tokenOut,
                    _info.targetPool.poolFee,
                    address(this),
                    block.timestamp,
                    _info.zeroToOne ? _amount0 : _amount1,
                    0,
                    0
                );
            IUniswapV3Router(_router).exactInputSingle(params);
        } else if (_info.targetPool.poolType == PoolType.Algebra) {
            address _router = routers[_info.targetPool.poolAddr];
            IERC20(_tokenIn).approve(_router, _amount0 > 0 ? _amount0 : _amount1);
            IAlgebraRouter.ExactInputSingleParams memory params = IAlgebraRouter
                .ExactInputSingleParams(
                    _tokenIn,
                    _tokenOut,
                    address(this),
                    block.timestamp,
                    _info.zeroToOne ? _amount0 : _amount1,
                    0,
                    0
                );
            IAlgebraRouter(_router).exactInputSingle(params);
        } else if (_info.targetPool.poolType == PoolType.KyberSwap) {
            address _router = routers[_info.targetPool.poolAddr];
            IERC20(_tokenIn).approve(_router, _amount0 > 0 ? _amount0 : _amount1);
            IKyberswapRouter.ExactInputSingleParams memory params = IKyberswapRouter
                .ExactInputSingleParams(
                    _tokenIn,
                    _tokenOut,
                    _info.targetPool.poolFee,
                    address(this),
                    block.timestamp,
                    _info.zeroToOne ? _amount0 : _amount1,
                    0,
                    0
                );
            IKyberswapRouter(_router).swapExactInputSingle(params);
        } else {
            revert UnknownPoolType();
        }
        IERC20(_tokenOut).safeTransfer(_info.flPool, _info.amountDebt);
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
        bool _zeroToOne,
        uint256 _amountInFlash,
        uint256 _amountOutFlash,
        ArbiterJob memory _job,
        ArbiterJobConfig memory _config
    ) internal view returns (uint32 _bestPoolIndex, uint256 _bestProfit) {
        uint256 _tempProfit;
        uint256 _amountOutExt;
        for (uint32 i = 0; i < _config.targetPools.length; ) {
            _amountOutExt = getAmountOut(
                _amountOutFlash,
                !_zeroToOne,
                _job.token0,
                _job.token1,
                _config.targetPools[i]
            );
            _tempProfit = _amountOutExt > _amountInFlash ? _amountOutExt - _amountInFlash : 0;
            if (_tempProfit > _bestProfit) {
                _bestPoolIndex = i;
                _bestProfit = _tempProfit;
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
        bytes calldata _checkData
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 _jobIndex = abi.decode(_checkData, (uint256));
        ArbiterJob memory _job = jobs[_jobIndex];
        ArbiterJobConfig memory _config = jobsConfig[_job.flPool];
        (uint256 _price0, uint256 _price1) = _getPrices(_job.token0, _job.token1);
        (
            bool _zeroToOne,
            uint256 _amountInFlash,
            uint256 _amountOutFlash,
            uint256 _minProfit
        ) = computeProfitMaximizingTrade(
                _job.flPool,
                _config.reserveToProfitRatio,
                _price0,
                _price1,
                _config.token0Decimals,
                _config.token1Decimals
            );
        if (_amountInFlash == 0) return (false, new bytes(0));
        (uint32 _bestPoolIndex, uint256 _bestProfit) = _findBestPool(
            _zeroToOne,
            _amountInFlash,
            _amountOutFlash,
            _job,
            _config
        );
        _bestProfit -= _bestProfit / _config.adjFactor;
        if (_bestProfit > _minProfit) {
            ArbiterCall memory _arbiterCall = ArbiterCall(
                uint32(_jobIndex),
                _amountInFlash,
                _amountOutFlash,
                _bestPoolIndex,
                _job.token0IsRewardToken == _zeroToOne,
                _zeroToOne
            );
            return(true, abi.encode(_arbiterCall));
        }
    }

    function performUpkeep(bytes calldata _performData) external override {
        ArbiterCall memory _call = abi.decode(_performData, (ArbiterCall));
        ArbiterJob memory _job = jobs[_call.jobIndex];
        CallbackData memory _callbackData = CallbackData(
            _job.flPool,
            jobsConfig[_job.flPool].targetPools[_call.bestPoolIndex],
            _job.token0,
            _job.token1,
            _call.amountInFlash,
            !_call.zeroToOne
        );
        permissionedPairAddress = _job.flPool;
        (IERC20 _tokenIn, IERC20 _tokenOut) = _call.zeroToOne
            ? (IERC20(_job.token0), IERC20(_job.token1))
            : (IERC20(_job.token1), IERC20(_job.token0));
        (uint256 _amount0Flash, uint256 _amount1Flash) = _call.zeroToOne
            ? (uint256(0), _call.amountOutFlash)
            : (_call.amountOutFlash, uint256(0));
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
            uint256 _balance = _profit + _balanceBefore;
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
