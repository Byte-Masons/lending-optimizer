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

    // 3rd-party contract addresses
    address public constant SPOOKY_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant TAROT_ROUTER = address(0x283e62CFe14b352dB8e30A9575481DCbf589Ad98);
    address public constant TAROT_REQUIEM_ROUTER = address(0x3F7E61C5dd29F9380b270551e438B65c29183a7c);
    address public constant TAROT_CARCOSA_ROUTER = address(0x26B21e8cd033ec68e4180DC5fc14446905E94572);

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
     * @dev Helper function to swap tokens given an {_amount}, swap {_path}, and {_router}.
     */
    function _swap(
        uint256 _amount,
        address[] memory _path,
        address _router
    ) internal {
        if (_path.length < 2 || _amount == 0) {
            return;
        }

        IERC20Upgradeable(_path[0]).safeIncreaseAllowance(_router, _amount);
        IUniswapV2Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
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

    function _processPool(address factory, address router, uint index) internal {
        address lpToken = IFactory(factory).allLendingPools(index);

        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();

        // if (token0 == want || token1 == want) {
                // nrOfWantPools++;
                // console.log("nrOfWantPools: ", nrOfWantPools);
                console.log("index: ", index);
                console.log("lpToken: ", lpToken);
                string memory token0Name = IERC20(token0).symbol();
                string memory token1Name = IERC20(token1).symbol();
                
                (address collateral,address borrowableA,address borrowableB) = IRouter(router).getLendingPool(lpToken);
                
                address underlying = IPoolToken(lpToken).underlying();
                
                uint totalBalance = IPoolToken(lpToken).totalBalance();
                
                uint underlyingWantBalance = IERC20Upgradeable(want).balanceOf(underlying);
                
                if (underlyingWantBalance > minWantInPool) {
                    console.log("token0: ", token0);
                    console.log("token1: ", token1);
                    console.log("token0Name: ", token0Name);
                    console.log("token1Name: ", token1Name);
                    console.log("collateral: ", collateral);
                    console.log("underlying: ", underlying);
                    console.log("totalBalance: ", totalBalance);
                    console.log("underlyingWantBalance: ", underlyingWantBalance);
                }
                console.log("--------------------------------------------");
            // }
    }

    //function getPrices() external returns (uint256 price0, uint256 price1);
    function getLendingPools() public {
        console.log("getLendingPools");
        // address factory = IRouter(TAROT_ROUTER).factory();
        // console.log("factory: ", factory);
        // uint nrOfPools = IFactory(factory).allLendingPoolsLength();
        // console.log("nrOfPools: ", nrOfPools);
        // uint nrOfWantPools = 0;
        // for (uint256 index = 0; index < nrOfPools; index++) {
        //     address lpToken = IFactory(factory).allLendingPools(index);

        // //     function getLendingPool(address uniswapV2Pair)
        // // external
        // // view
        // // returns (
        // //     address collateral,
        // //     address borrowableA,
        // //     address borrowableB
        // // );
            
        //     address token0 = IUniswapV2Pair(lpToken).token0();
        //     address token1 = IUniswapV2Pair(lpToken).token1();
        //     // if (token0 == want || token1 == want) {
        //         nrOfWantPools++;
        //         console.log("nrOfWantPools: ", nrOfWantPools);
        //         console.log("lpToken: ", lpToken);
        //         string memory token0Name = IERC20(token0).symbol();
        //         string memory token1Name = IERC20(token1).symbol();
        //         console.log("token0: ", token0);
        //         console.log("token1: ", token1);
        //         console.log("token0Name: ", token0Name);
        //         console.log("token1Name: ", token1Name);
        //         (address collateral,address borrowableA,address borrowableB) = IRouter(TAROT_ROUTER).getLendingPool(lpToken);
        //         console.log("collateral: ", collateral);
        //         console.log("--------------------------------------------");
        //     // }
        // }

        address requiemFactory = IRouter(TAROT_REQUIEM_ROUTER).factory();
        uint nrOfPools = IFactory(requiemFactory).allLendingPoolsLength();

        for (uint256 index = 0; index < nrOfPools; index++) {
            _processPool(requiemFactory, TAROT_REQUIEM_ROUTER, index);
        }

        // address carcosaFactory = IRouter(TAROT_CARCOSA_ROUTER).factory();
        // uint nrOfPools = IFactory(carcosaFactory).allLendingPoolsLength();

        // for (uint256 index = 0; index < nrOfPools; index++) {
        //     _processPool(carcosaFactory, TAROT_CARCOSA_ROUTER, index);
        // }
    }
}
