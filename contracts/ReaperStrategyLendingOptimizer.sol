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

interface IERC20 {
    function name() external view returns (string memory);

    function symbol() external pure returns (string memory);
}

/**
 * @dev Deposits want in Tarot, Alpaca or Alpha Homora lending pools for the highest APRs.
 */
contract ReaperStrategyLendingOptimizer is ReaperBaseStrategyv2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    struct PoolAllocation {
        address poolAddress;
        uint allocation;
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
    uint public minWantInPool;
    EnumerableSetUpgradeable.AddressSet private usedPools;
    uint constant public MAX_POOLS = 20;
    enum RouterType{ CLASSIC, REQUIEM }
    address public depositPool;
    uint256 public sharePriceSnapshot;
    uint256 public minProfitToChargeFees;
    uint256 public withdrawSlippageTolerance;

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
        sharePriceSnapshot = 0;
        minProfitToChargeFees = 1000;
        sharePriceSnapshot = IVault(_vault).getPricePerFullShare();
        withdrawSlippageTolerance = 50;
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).transfer(depositPool, wantBalance);
            require(IBorrowable(depositPool).mint(address(this)) >= 0);
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
        // keep track of how much we need to withdraw
        uint256 remainingUnderlyingNeeded = _amountToWithdraw;
        uint256 withdrawn;

        address[] memory pools = usedPools.values();
        for (uint256 index = 0; index < pools.length; index++) {
            // save some gas by storing locally
            address currentPool = pools[index];
            IBorrowable(currentPool).exchangeRate();

            // how much want our strategy has supplied to this pool
            uint256 suppliedToPool = wantSuppliedToPool(currentPool);

            // total liquidity available in the pool in want
            uint256 poolAvailableWant = IERC20Upgradeable(want).balanceOf(currentPool);

            // the minimum of the previous two values is the most want we can withdraw from this pool
            uint256 ableToPullInUnderlying = MathUpgradeable.min(suppliedToPool, poolAvailableWant);

            // skip ahead to our next loop if we can't withdraw anything
            if (ableToPullInUnderlying == 0) {
                continue;
            }

            // figure out how much bToken we are able to burn from this pool for want.
            uint256 ableToPullInbToken = ableToPullInUnderlying * 1 ether / IBorrowable(currentPool).exchangeRateLast();

            // check if we need to pull as much as possible from our pools
            if (_amountToWithdraw == type(uint256).max) {
                // this is for withdrawing the maximum we safely can
                if (poolAvailableWant > suppliedToPool) {
                    // if possible, burn our whole bToken position to avoid dust
                    uint256 balanceOfbToken = IBorrowable(currentPool).balanceOf(address(this));
                    IBorrowable(currentPool).transfer(currentPool, balanceOfbToken);
                    IBorrowable(currentPool).redeem(address(this));
                } else {
                    // otherwise, withdraw as much as we can
                    IBorrowable(currentPool).transfer(currentPool, ableToPullInbToken);
                    IBorrowable(currentPool).redeem(address(this));
                }
                continue;
            }

            // this is how much we need, converted to the bTokens of this specific pool. add 5 wei as a buffer for calculation losses.
            uint256 remainingbTokenNeeded =
                remainingUnderlyingNeeded * 1 ether / IBorrowable(currentPool).exchangeRateLast() + 5;

            // Withdraw all we need from the current pool if we can
            if (ableToPullInbToken > remainingbTokenNeeded) {
                IBorrowable(currentPool).transfer(currentPool, remainingbTokenNeeded);
                uint256 pulled = IBorrowable(currentPool).redeem(address(this));

                // add what we just withdrew to our total
                withdrawn = withdrawn + pulled;
                break;
            }
            //Otherwise withdraw what we can from current pool
            else {
                // if there is more free liquidity than our amount deposited, just burn the whole bToken balance so we don't have dust
                uint256 pulled;
                if (poolAvailableWant > suppliedToPool) {
                    uint256 balanceOfbToken = IBorrowable(currentPool).balanceOf(address(this));
                    IBorrowable(currentPool).transfer(currentPool, balanceOfbToken);
                    pulled = IBorrowable(currentPool).redeem(address(this));
                } else {
                    IBorrowable(currentPool).transfer(currentPool, ableToPullInbToken);
                    pulled = IBorrowable(currentPool).redeem(address(this));
                }
                // add what we just withdrew to our total, subtract it from what we still need
                withdrawn = withdrawn + pulled;

                // don't want to overflow
                if (remainingUnderlyingNeeded > pulled) {
                    remainingUnderlyingNeeded = remainingUnderlyingNeeded - pulled;
                } else {
                    remainingUnderlyingNeeded = 0;
                }
            }
        }
        return withdrawn;
    }

    function rebalance(PoolAllocation[] memory _allocations) external {
        _onlyKeeper();
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
            IERC20Upgradeable(want).transfer(pool, depositAmount);
            require(IBorrowable(pool).mint(address(this)) >= 0);
        }
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
    function _chargeFees() internal {
        uint256 profit = profitSinceHarvest();
        if (profit >= minProfitToChargeFees) {
            uint256 wftmFee = 0;
            IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
            if (want != WFTM) {
                _swap(want, WFTM, profit * totalFee / PERCENT_DIVISOR);
                wftmFee = wftm.balanceOf(address(this));
            } else {
                wftmFee = profit * totalFee / PERCENT_DIVISOR;
            }
            
            if (wftmFee != 0) {
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
        address[] memory pools = usedPools.values();
        for (uint256 index = 0; index < pools.length; index++) {
            address pool = pools[index];
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
        address[] memory pools = usedPools.values();
        for (uint256 index = 0; index < pools.length; index++) {
            poolBalance += wantSuppliedToPool(pools[index]);
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
        uint256 sharePriceChange = IVault(vault).getPricePerFullShare() - sharePriceSnapshot;
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

    function addUsedPool(uint _poolIndex, RouterType _routerType) external {
        _onlyKeeper();
        
        address router;

        if (_routerType == RouterType.CLASSIC) {
            router = TAROT_ROUTER;
        } else if (_routerType == RouterType.REQUIEM) {
            router = TAROT_REQUIEM_ROUTER;
        }

        address factory = IRouter(router).factory();
        address poolAddress = IFactory(factory).allLendingPools(_poolIndex);
        bool isPoolAlreadyAdded = usedPools.contains(poolAddress);
        require(!isPoolAlreadyAdded, "Pool already added");
        require(IBorrowable(poolAddress).underlying() == want, "Pool underlying != want");
        
        usedPools.add(poolAddress);
    }

    /**
     * @dev Removes a pool that will no longer be used.
     */
    function removeUsedPool(address _pool) external {
        _onlyStrategistOrOwner();
        require(usedPools.length() > 1, "Must have at least 1 pool");
        require(usedPools.contains(_pool), "Pool not used");
        uint256 wantSupplied = wantSuppliedToPool(_pool);
        if (wantSupplied > 0) {
            uint256 wantAvailable = IERC20Upgradeable(want).balanceOf(_pool);
            uint256 currentExchangeRate = IBorrowable(_pool).exchangeRate();
            uint256 ableToPullInUnderlying = MathUpgradeable.min(wantSupplied, wantAvailable);
            uint256 ableToPullInbToken = ableToPullInUnderlying * 1 ether / currentExchangeRate;
            if (ableToPullInbToken > 0) {
                IBorrowable(_pool).transfer(_pool, ableToPullInbToken);
                IBorrowable(_pool).redeem(address(this));
            }
            wantSupplied = wantSuppliedToPool(_pool);
        }
        require(wantSupplied == 0, "Want is still supplied to the pool");
        usedPools.remove(_pool);
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
}
