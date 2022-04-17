// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv2.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPoolToken.sol";
import "./interfaces/ICollateral.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "hardhat/console.sol";

interface IERC20 {
    function name() external view returns (string memory);

    function symbol() external pure returns (string memory);
}

/**
 * @dev Deposits want in Tarot, Alpaca or Alpha Homora lending pools for the highest APRs.
 */
contract ReaperStrategyLendingOptimizer is ReaperBaseStrategyv2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Pool {
        uint poolIndex;
        RouterType router;
        address poolAddress;
    }

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    EnumerableSetUpgradeable.AddressSet private pools;

    // 3rd-party contract addresses
    address public constant SPOOKY_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant TAROT_ROUTER = address(0x283e62CFe14b352dB8e30A9575481DCbf589Ad98);
    address public constant TAROT_REQUIEM_ROUTER = address(0x3F7E61C5dd29F9380b270551e438B65c29183a7c);

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps.
     * {want} - Address of the token being lent
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant want = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    /**
     * @dev Paths used to swap tokens:
     * {tshareToWftmPath} - to swap {TSHARE} to {WFTM} (using SPOOKY_ROUTER)
     * {wftmToTombPath} - to swap {WFTM} to {lpToken0} (using SPOOKY_ROUTER)
     * {tombToMaiPath} - to swap half of {lpToken0} to {lpToken1} (using TOMB_ROUTER)
     */
    address[] public tshareToWftmPath;
    address[] public wftmToTombPath;
    address[] public tombToMaiPath;

    /**
     * @dev Tarot variables
     * {poolId} - ID of pool in which to deposit LP tokens
     */
    uint public minWantInPool;
    Pool[] public usedPools;
    uint constant public MAX_POOLS = 20;
    enum RouterType{ CLASSIC, REQUIEM }

    /**
     * @dev Initializes the strategy. Sets parameters and saves routes.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        minWantInPool = 5 ether;
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        // uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        // if (wantBalance != 0) {
        //     IERC20Upgradeable(want).safeIncreaseAllowance(TSHARE_REWARDS_POOL, wantBalance);
        //     IMasterChef(TSHARE_REWARDS_POOL).deposit(poolId, wantBalance);
        // }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        // uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        // if (wantBal < _amount) {
        //     IMasterChef(TSHARE_REWARDS_POOL).withdraw(poolId, _amount - wantBal);
        // }

        // IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {TSHARE} from the {TSHARE_REWARDS_POOL}.
     *      2. Swaps {TSHARE} to {WFTM} using {SPOOKY_ROUTER}.
     *      3. Claims fees for the harvest caller and treasury.
     *      4. Swaps the {WFTM} token for {lpToken0} using {SPOOKY_ROUTER}.
     *      5. Swaps half of {lpToken0} to {lpToken1} using {TOMB_ROUTER}.
     *      6. Creates new LP tokens and deposits.
     */
    function _harvestCore() internal override {
        // IMasterChef(TSHARE_REWARDS_POOL).deposit(poolId, 0); // deposit 0 to claim rewards

        // uint256 tshareBal = IERC20Upgradeable(TSHARE).balanceOf(address(this));
        // _swap(tshareBal, tshareToWftmPath, SPOOKY_ROUTER);

        // _chargeFees();

        // uint256 wftmBal = IERC20Upgradeable(WFTM).balanceOf(address(this));
        // _swap(wftmBal, wftmToTombPath, SPOOKY_ROUTER);
        // uint256 tombHalf = IERC20Upgradeable(lpToken0).balanceOf(address(this)) / 2;
        // _swap(tombHalf, tombToMaiPath, TOMB_ROUTER);

        // _addLiquidity();
        // deposit();
    }

    /**
     * @dev Helper function to swap tokens given an {_amount}, swap {_path}, and {_routerType}.
     */
    function _swap(
        uint256 _amount,
        address[] memory _path,
        address _routerType
    ) internal {
        if (_path.length < 2 || _amount == 0) {
            return;
        }

        IERC20Upgradeable(_path[0]).safeIncreaseAllowance(_routerType, _amount);
        IUniswapV2Router02(_routerType).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            _path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmFee = (wftm.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidity() internal {
        // uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        // uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        // if (lp0Bal != 0 && lp1Bal != 0) {
        //     IERC20Upgradeable(lpToken0).safeIncreaseAllowance(TOMB_ROUTER, lp0Bal);
        //     IERC20Upgradeable(lpToken1).safeIncreaseAllowance(TOMB_ROUTER, lp1Bal);
        //     IUniswapV2Router02(TOMB_ROUTER).addLiquidity(
        //         lpToken0,
        //         lpToken1,
        //         lp0Bal,
        //         lp1Bal,
        //         0,
        //         0,
        //         address(this),
        //         block.timestamp
        //     );
        // }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in the MasterChef.
     */
    function balanceOf() public view override returns (uint256) {
        // (uint256 amount, ) = IMasterChef(TSHARE_REWARDS_POOL).userInfo(poolId, address(this));
        // return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        // uint256 pendingReward = IMasterChef(TSHARE_REWARDS_POOL).pendingShare(poolId, address(this));
        // uint256 totalRewards = pendingReward + IERC20Upgradeable(TSHARE).balanceOf(address(this));

        // if (totalRewards != 0) {
        //     profit += IUniswapV2Router02(SPOOKY_ROUTER).getAmountsOut(totalRewards, tshareToWftmPath)[1];
        // }

        // profit += IERC20Upgradeable(WFTM).balanceOf(address(this));

        // uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        // callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        // profit -= wftmFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function _retireStrat() internal override {
        // IMasterChef(TSHARE_REWARDS_POOL).deposit(poolId, 0); // deposit 0 to claim rewards

        // uint256 tshareBal = IERC20Upgradeable(TSHARE).balanceOf(address(this));
        // _swap(tshareBal, tshareToWftmPath, SPOOKY_ROUTER);

        // uint256 wftmBal = IERC20Upgradeable(WFTM).balanceOf(address(this));
        // _swap(wftmBal, wftmToTombPath, SPOOKY_ROUTER);
        // uint256 tombHalf = IERC20Upgradeable(lpToken0).balanceOf(address(this)) / 2;
        // _swap(tombHalf, tombToMaiPath, TOMB_ROUTER);

        // _addLiquidity();

        // (uint256 poolBal, ) = IMasterChef(TSHARE_REWARDS_POOL).userInfo(poolId, address(this));
        // IMasterChef(TSHARE_REWARDS_POOL).withdraw(poolId, poolBal);

        // uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        // IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        // IMasterChef(TSHARE_REWARDS_POOL).emergencyWithdraw(poolId);
    }

    // function allLendingPools(uint) external view returns (address uniswapV2Pair);
	// function allLendingPoolsLength() external view returns (uint);

    // function _processPool(address factory, address router, uint index) internal {
    //     address poolToken = IFactory(factory).allLendingPools(index);

    //     address token0 = IUniswapV2Pair(poolToken).token0();
    //     address token1 = IUniswapV2Pair(poolToken).token1();

    //     if (token0 == want || token1 == want) {
            
                
    //         // (address collateral,address borrowableA,address borrowableB) = IRouter(router).getLendingPool(poolToken);

    //         // console.log(IPoolToken(poolToken).name());
    //         // string memory tokenName = IPoolToken(poolToken).name();
    //         // console.log(poolToken);
    //         // Filter out these tokens as they are not pool tokens but somehow are in the list
    //         if (poolToken != address(0x84311ECC54D7553378c067282940b0fdfb913675) &&
    //         poolToken != address(0xA48869049e36f8Bfe0Cc5cf655632626988c0140)) {
    //             string memory token0Name = IERC20(token0).symbol();
    //             string memory token1Name = IERC20(token1).symbol();
    //             console.log(token0Name, "-", token1Name);
    //             usedPools.push(poolToken);
    //             // address underlying = IPoolToken(poolToken).underlying();
    //             // uint underlyingWantBalance = IERC20Upgradeable(want).balanceOf(underlying);
    //             // if (underlyingWantBalance > minWantInPool) {
                    
    //             // }
    //         }

    //         // // uint totalBalance = IPoolToken(poolToken).totalBalance();
                
    //         // uint underlyingWantBalance = IERC20Upgradeable(want).balanceOf(underlying);
                
    //         // if (underlyingWantBalance > minWantInPool) {
    //         //     // usedPools.push(poolToken);
    //         // }
    //     }
    // }

    // function setUsedPools() public {
    //     address factory = IRouter(TAROT_ROUTER).factory();
    //     uint nrOfPools = IFactory(factory).allLendingPoolsLength();
    //     for (uint256 index = 0; index < nrOfPools; index++) {
    //         _processPool(factory, TAROT_ROUTER, index);
    //     }

    //     address requiemFactory = IRouter(TAROT_REQUIEM_ROUTER).factory();
    //     nrOfPools = IFactory(requiemFactory).allLendingPoolsLength();

    //     for (uint256 index = 0; index < nrOfPools; index++) {
    //         _processPool(requiemFactory, TAROT_REQUIEM_ROUTER, index);
    //     }
    // }

    function addUsedPool(uint _poolIndex, RouterType _routerType) external {
        _onlyStrategistOrOwner();
        bool isPoolAlreadyAdded = false;
        for (uint256 index = 0; index < usedPools.length; index++) {
            uint currentPool = usedPools[index].poolIndex;
            if (_poolIndex == currentPool) {
                isPoolAlreadyAdded = true;
                break;
            }
        }
        require(!isPoolAlreadyAdded, "Pool already added");

        address router;

        if (_routerType == RouterType.CLASSIC) {
            router = TAROT_ROUTER;
        } else if (_routerType == RouterType.REQUIEM) {
            router = TAROT_REQUIEM_ROUTER;
        }

        address factory = IRouter(router).factory();
        address poolAddress = IFactory(factory).allLendingPools(_poolIndex);

        Pool memory pool = Pool(_poolIndex, _routerType, poolAddress);
        usedPools.push(pool);
        pools.add(poolAddress);
    }

    /**
     * @dev Removes a pool that will no longer be used.
     */
    function removeUsedPool(uint256 _poolIndex) external {
        _onlyStrategistOrOwner();
        require(usedPools.length > 1, "Must have at least 1 pool");
        // address poolToRemove = usedPools[_poolIndex];
        // // uint256 balance = poolxTokenBalance[poolId];
        // // _aceLabWithdraw(poolId, balance);
        // uint lastPoolIndex = usedPools.length - 1;
        // address lastPool = usedPools[lastPoolIndex];
        // usedPools[_poolIndex] = lastPool;
        // usedPools.pop();
    }

    // function _isAddressTarotPool(address _pool, address _routerType) internal view returns (bool) {
    //     address factory = IRouter(_routerType).factory();
    //     uint nrOfPools = IFactory(factory).allLendingPoolsLength();
    //     bool isTarotPool = false;
    //     for (uint256 index = 0; index < nrOfPools; index++) {
    //         address currentPool = IFactory(factory).allLendingPools(index);
    //         if (_pool == currentPool) {
    //             isTarotPool = true;
    //             break;
    //         }
    //     }
    //     return isTarotPool;
    // }
}
