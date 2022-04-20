// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv2.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPoolToken.sol";
import "./interfaces/ICollateral.sol";
import "./interfaces/IBorrowable.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "hardhat/console.sol";

/**
 * @dev Deposits want in Tarot lending pools for the highest APRs.
 */
contract ReaperStrategyLendingOptimizer is ReaperBaseStrategyv2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    struct PoolAllocation {
        address poolAddress;
        uint allocation;
    }

    struct Pool {
        RouterType routerType;
        uint index;
    }

    /**
     * Reaper Roles
     */
    bytes32 public constant KEEPER = keccak256("KEEPER");
    
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
     * @dev Tarot variables
     */
    EnumerableSetUpgradeable.AddressSet private usedPools;
    uint constant public MAX_POOLS = 20;
    enum RouterType{ CLASSIC, REQUIEM }
    address public depositPool;
    uint256 public sharePriceSnapshot;
    uint256 public minProfitToChargeFees;
    uint256 public withdrawSlippageTolerance;
    uint public minWantToDepositOrWithdraw;
    uint public minWantToRemovePool;

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
        sharePriceSnapshot = IVault(_vault).getPricePerFullShare();
        withdrawSlippageTolerance = 50;
        minProfitToChargeFees = 1000;
        minWantToDepositOrWithdraw = 10;
        minWantToRemovePool = 100;
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = balanceOfWant();
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeTransfer(depositPool, wantBalance);
            uint256 minted = IBorrowable(depositPool).mint(address(this));
            require(minted != 0, "Cannot mint 0");
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 initialWithdrawAmount = _amount;
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            uint256 withdrawn = _withdrawUnderlying(_amount - wantBal);
            if (withdrawn + wantBal < _amount) {
                _amount = withdrawn + wantBal;
            }
        }

        if(_amount < initialWithdrawAmount) {
            require(
                _amount >=
                    (initialWithdrawAmount *
                        (PERCENT_DIVISOR - withdrawSlippageTolerance)) /
                        PERCENT_DIVISOR
            );
        }

        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    function _withdrawUnderlying(uint256 _amountToWithdraw) internal returns (uint256) {
        uint256 remainingUnderlyingNeeded = _amountToWithdraw;
        uint256 withdrawn = 0;

        // address[] memory pools = usedPools.values();
        for (uint256 index = 0; index < usedPools.length(); index++) {
            address currentPool = usedPools.at(index);
            console.log("currentPool: ", currentPool);
            uint256 exchangeRate = IBorrowable(currentPool).exchangeRate();

            uint256 suppliedToPool = wantSuppliedToPool(currentPool);
            console.log("suppliedToPool: ", suppliedToPool);

            uint256 poolAvailableWant = IERC20Upgradeable(want).balanceOf(currentPool);

            uint256 ableToPullInUnderlying = MathUpgradeable.min(suppliedToPool, poolAvailableWant);
            console.log("ableToPullInUnderlying: ", ableToPullInUnderlying);
            console.log("remainingUnderlyingNeeded: ", remainingUnderlyingNeeded);

            uint256 underlyingToWithdraw = MathUpgradeable.min(remainingUnderlyingNeeded, ableToPullInUnderlying);

            if (underlyingToWithdraw < minWantToDepositOrWithdraw) {
                continue;
            }

            uint256 bTokenToWithdraw = underlyingToWithdraw * 1 ether / exchangeRate;
            console.log("underlyingToWithdraw: ", underlyingToWithdraw);
            console.log("bTokenToWithdraw: ", bTokenToWithdraw);

            IBorrowable(currentPool).transfer(currentPool, bTokenToWithdraw);
            withdrawn += IBorrowable(currentPool).redeem(address(this));

            if (withdrawn >= _amountToWithdraw - minWantToDepositOrWithdraw) {
                break;
            }

            remainingUnderlyingNeeded = _amountToWithdraw - withdrawn;
        }
        return withdrawn;
    }

    function rebalance(PoolAllocation[] memory _allocations) external {
        _onlyKeeper();
        console.log("rebalance()");
        console.log("balanceOfWant()", balanceOfWant());
        console.log("balanceOfPools()", balanceOfPools());
        for (uint256 index = 0; index < _allocations.length; index++) {
            address pool = _allocations[index].poolAddress;
            require(usedPools.contains(pool), "Pool is not authorized");
            
            // Save the top APR pool to deposit in to
            if (index == 0) {
                depositPool = pool;
            }

            uint wantAvailable = IERC20Upgradeable(want).balanceOf(address(this));
            if (wantAvailable == 0) {
                return;
            }
            uint allocation = _allocations[index].allocation;
            uint depositAmount = MathUpgradeable.min(wantAvailable, allocation);
            IERC20Upgradeable(want).safeTransfer(pool, depositAmount);
            uint256 minted = IBorrowable(pool).mint(address(this));
            require(minted != 0, "Cannot mint 0");
            console.log("balanceOfWant()", balanceOfWant());
            console.log("balanceOfPools()", balanceOfPools());
        }
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > minWantToDepositOrWithdraw) {
            IERC20Upgradeable(want).safeTransfer(depositPool, wantBalance);
            uint256 minted = IBorrowable(depositPool).mint(address(this));
            require(minted != 0, "Cannot mint 0");
        }
        console.log("balanceOfWant()", balanceOfWant());
        console.log("balanceOfPools()", balanceOfPools());
    }

    /**
     * @dev Harvest is not strictly necessary since only fees are claimed
     *      but it is kept here for compatibility
     *      1. Claims fees for the harvest caller and treasury.
     */
    function _harvestCore() internal override {
        _chargeFees();
    }

    /**
     * @dev Helper function to swap tokens given {_from}, {_to} and {_amount}
     */
    function _swap(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_from == _to || _amount == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;
        IUniswapV2Router02(SPOOKY_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal { // planning to call this from withdraw as well?
        console.log("_chargeFees()");
        updateExchangeRates();
        uint256 profit = profitSinceHarvest();
        console.log("profit: ", profit);
        if (profit >= minProfitToChargeFees) {
            uint256 wftmFee = 0;
            IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
            if (want != WFTM) {
                _swap(want, WFTM, profit * totalFee / PERCENT_DIVISOR);
                wftmFee = wftm.balanceOf(address(this));
            } else {
                wftmFee = profit * totalFee / PERCENT_DIVISOR;
            }
            console.log("wftmFee: ", wftmFee);
            
            if (wftmFee != 0) {
                uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
                if (wantBal < wftmFee) {
                    uint256 withdrawn = _withdrawUnderlying(wftmFee - wantBal);
                    if (withdrawn + wantBal < wftmFee) {
                        wftmFee = withdrawn + wantBal;
                    }
                }
                uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
                uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
                uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
                treasuryFeeToVault -= feeToStrategist;

                wftm.safeTransfer(msg.sender, callFeeToUser);
                wftm.safeTransfer(treasury, treasuryFeeToVault);
                wftm.safeTransfer(strategistRemitter, feeToStrategist);
            }
            sharePriceSnapshot = IVault(vault).getPricePerFullShare();
        }
    }

    function updateExchangeRates() public {
        for (uint256 index = 0; index < usedPools.length(); index++) {
            address pool = usedPools.at(index);
            IBorrowable(pool).exchangeRate();
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in the MasterChef.
     */
    function balanceOf() public view override returns (uint256) {
        return balanceOfWant() + balanceOfPools();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    function balanceOfPools() public view returns (uint256) {
        uint256 poolBalance = 0;
        for (uint256 index = 0; index < usedPools.length(); index++) {
            poolBalance += wantSuppliedToPool(usedPools.at(index));
        }
        return poolBalance;
    }

    /**
     * @dev Returns the amount of want supplied to a lending pool.
     */
    function wantSuppliedToPool(address _pool) public view returns (uint256 wantBal) {
        uint256 bTokenBalance = IBorrowable(_pool).balanceOf(address(this));
        uint256 currentExchangeRate = IBorrowable(_pool).exchangeRateLast();
        wantBal = bTokenBalance * currentExchangeRate / 1 ether;
    }

    function profitSinceHarvest() public view returns (uint256 profit) {
        uint256 ppfs = IVault(vault).getPricePerFullShare();
        console.log("profitSinceHarvest()");
        console.log("ppfs: ", ppfs);
        console.log("sharePriceSnapshot: ", sharePriceSnapshot);
        if (ppfs <= sharePriceSnapshot) {
            return 0;
        }
        uint256 sharePriceChange = ppfs - sharePriceSnapshot;
        console.log("sharePriceChange: ", sharePriceChange);
        profit = balanceOf() * sharePriceChange / 1 ether;
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 profitInWant = profitSinceHarvest();
        if (want != WFTM) {
            address[] memory rewardToWftmPath = new address[](2);
            rewardToWftmPath[0] = want;
            rewardToWftmPath[1] = WFTM;
            uint256[] memory amountOutMins = IUniswapV2Router02(SPOOKY_ROUTER).getAmountsOut(
                profitInWant,
                rewardToWftmPath
            );
            profit += amountOutMins[1];
        } else {
            profit += profitInWant;
        }
        
        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function _retireStrat() internal override {
        uint256 suppliedBalance = balanceOfPools();
        require(suppliedBalance <= minWantToRemovePool, "Want still supplied to pools");
        uint256 wantBalance = balanceOfWant();
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * Withdraws all funds
     */
    function _reclaimWant() internal override {
        _withdrawUnderlying(type(uint256).max);
    }

    /**
     * Withdraws all funds
     */
    function reclaimWant() public  {
         _onlyKeeper();
        _reclaimWant();
    }

    function addUsedPools(Pool[] memory _poolsToAdd) external {
        _onlyKeeper();
        for (uint256 index = 0; index < _poolsToAdd.length; index++) {
            Pool memory pool = _poolsToAdd[index];
            addUsedPool(pool.index, pool.routerType);
        }
    }

    function addUsedPool(uint _poolIndex, RouterType _routerType) public {
        _onlyKeeper();
        
        address router;
        console.log("_poolIndex: ", _poolIndex);
        console.log("_routerType: ", uint(_routerType));

        if (_routerType == RouterType.CLASSIC) {
            router = TAROT_ROUTER;
        } else if (_routerType == RouterType.REQUIEM) {
            router = TAROT_REQUIEM_ROUTER;
        }
        console.log("router: ", router);

        address factory = IRouter(router).factory();
        address lpAddress = IFactory(factory).allLendingPools(_poolIndex);
        console.log("lpAddress: ", lpAddress);
        address lp0 = IUniswapV2Pair(lpAddress).token0();
        address lp1 = IUniswapV2Pair(lpAddress).token1();
        console.log("lp0: ", lp0);
        console.log("lp1: ", lp1);
        bool containsWant = lp0 == want || lp1 == want;
        require(containsWant, "Pool does not contain want");
        (,,,address borrowable0, address borrowable1) = IFactory(factory).getLendingPool(lpAddress);
        address poolAddress = lp0 == want ? borrowable0 : borrowable1;
        bool isPoolAlreadyAdded = usedPools.contains(poolAddress);
        require(!isPoolAlreadyAdded, "Pool already added");
        require(usedPools.length() < MAX_POOLS, "Reached max nr of pools");
        
        usedPools.add(poolAddress);
    }

    function withdrawFromPool(address _pool) external returns (uint256) {
        _onlyKeeper();
        uint256 wantSupplied = wantSuppliedToPool(_pool);
        if (wantSupplied != 0) { // if (wantSupplied > 1e5) could probably make the min value configurable
            uint256 wantAvailable = IERC20Upgradeable(want).balanceOf(_pool);
            uint256 currentExchangeRate = IBorrowable(_pool).exchangeRate();
            uint256 ableToPullInUnderlying = MathUpgradeable.min(wantSupplied, wantAvailable);
            uint256 ableToPullInbToken = ableToPullInUnderlying * 1 ether / currentExchangeRate;
            if (ableToPullInbToken != 0) {
                IBorrowable(_pool).transfer(_pool, ableToPullInbToken);
                IBorrowable(_pool).redeem(address(this));
            }
            wantSupplied = wantSuppliedToPool(_pool);
        }
        return wantSupplied;
    }

    /**
     * @dev Removes a pool that will no longer be used.
     */
    function removeUsedPool(address _pool) external {
        _onlyKeeper();
        require(usedPools.length() > 1, "Must have at least 1 pool");
        require(usedPools.contains(_pool), "Pool not used");
        uint256 wantSupplied = wantSuppliedToPool(_pool);
        require(wantSupplied < minWantToRemovePool, "Want is still supplied"); // should there be a min that we don't care about? like 10^5 or something
        
        usedPools.remove(_pool);
        if (_pool == depositPool) {
            depositPool = usedPools.at(0);
        }
    }

    /**
     * @dev Only allow access to keeper and above
     */
    function _onlyKeeper() internal view {
        require(hasRole(KEEPER, msg.sender) || hasRole(STRATEGIST, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");
    }

    /**
     * @dev Sets the maximum slippage authorized when withdrawing
     */
    function setWithdrawSlippageTolerance(uint256 _withdrawSlippageTolerance) external {
        _onlyStrategistOrOwner();
        withdrawSlippageTolerance = _withdrawSlippageTolerance;
    }

    /**
     * @dev Sets the minimum amount of profit (in want) to charge fees
     */
    function setMinProfitToChargeFees(uint256 _minProfitToChargeFees) external {
        _onlyStrategistOrOwner();
        minProfitToChargeFees = _minProfitToChargeFees;
    }

    /**
     * @dev Sets the minimum amount of want to deposit or withdraw out of a pool
     */
    function setMinWantToDepositOrWithdraw(uint256 _minWantToDepositOrWithdraw) external {
        _onlyStrategistOrOwner();
        minWantToDepositOrWithdraw = _minWantToDepositOrWithdraw;
    }

    /**
     * @dev Sets the minimum amount of want lost when removing a pool
     */
    function setMinWantToRemovePool(uint256 _minWantToRemovePool) external {
        _onlyStrategistOrOwner();
        minWantToRemovePool = _minWantToRemovePool;
    }
}
