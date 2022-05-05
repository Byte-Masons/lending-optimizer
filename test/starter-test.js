const hre = require('hardhat');
const chai = require('chai');
const {solidity} = require('ethereum-waffle');
chai.use(solidity);
const {expect} = chai;

const moveTimeForward = async (seconds) => {
  await network.provider.send('evm_increaseTime', [seconds]);
  await network.provider.send('evm_mine');
};

// use with small values in case harvest is block-dependent instead of time-dependent
const moveBlocksForward = async (blocks) => {
  for (let i = 0; i < blocks; i++) {
    await network.provider.send('evm_increaseTime', [1]);
    await network.provider.send('evm_mine');
  }
};

const toWantUnit = (num, decimals) => {
  if (decimals) {
    return ethers.BigNumber.from(num * 10 ** decimals);
  }
  return ethers.utils.parseEther(num);
};

const addUsedPools = async (strategy) => {
  const pools = [
    {
      routerType: 1,
      index: 24,
    },
  ];
  await strategy.addUsedPools(pools);
};

const rebalance = async (strategy) => {
  const poolAllocations = [
    {
      poolAddress: '0x967A31b5ad8D194cef342397658b1F8A7e40bCAa',
      allocation: ethers.BigNumber.from('654925862235622915903'),
    },
    {
      poolAddress: '0xF0763274fD6578077cE687F2C0AbE92a1CFa3b1d',
      allocation: ethers.BigNumber.from('65391926615092011295'),
    },
  ];
  await strategy.rebalance(poolAllocations);
};

describe('Vaults', function () {
  let Vault;
  let vault;

  let Strategy;
  let strategy;

  let Want;
  let want;

  const treasuryAddr = '0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b';
  const paymentSplitterAddress = '0x63cbd4134c2253041F370472c130e92daE4Ff174';
  const wantAddress = '0x321162Cd933E2Be498Cd2267a90534A804051b11';

  const wantHolderAddr = '0x3ade6ad8d661ed9a673669df402c6bee13c3857a';
  const strategistAddr = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';

  let owner;
  let wantHolder;
  let strategist;

  beforeEach(async function () {
    //reset network
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: 'https://rpc.ftm.tools/',
            blockNumber: 37630648,
          },
        },
      ],
    });

    //get signers
    [owner] = await ethers.getSigners();
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [wantHolderAddr],
    });
    wantHolder = await ethers.provider.getSigner(wantHolderAddr);
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [strategistAddr],
    });
    strategist = await ethers.provider.getSigner(strategistAddr);

    //get artifacts
    Vault = await ethers.getContractFactory('ReaperVaultv1_4');
    Strategy = await ethers.getContractFactory('ReaperStrategyLendingOptimizer');
    Want = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
    const poolIndex = 37;
    const routerType = 0;

    //deploy contracts
    vault = await Vault.deploy(wantAddress, 'TOMB-MAI Tomb Crypt', 'rf-TOMB-MAI', 0, ethers.constants.MaxUint256);
    strategy = await hre.upgrades.deployProxy(
      Strategy,
      [vault.address, [treasuryAddr, paymentSplitterAddress], [strategistAddr], poolIndex, routerType],
      {kind: 'uups'},
    );
    await strategy.deployed();
    await vault.initialize(strategy.address);
    want = await Want.attach(wantAddress);

    //approving LP token and vault share spend
    await want.connect(wantHolder).approve(vault.address, ethers.constants.MaxUint256);

    await addUsedPools(strategy);
    await rebalance(strategy);
  });

  describe('Deploying the vault and strategy', function () {
    xit('should initiate vault with a 0 balance', async function () {
      const totalBalance = await vault.balance();
      const availableBalance = await vault.available();
      const pricePerFullShare = await vault.getPricePerFullShare();
      expect(totalBalance).to.equal(0);
      expect(availableBalance).to.equal(0);
      expect(pricePerFullShare).to.equal(ethers.utils.parseEther('1'));
    });
  });

  describe('Vault Tests', function () {
    xit('should allow deposits and account for them correctly', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const vaultBalance = await vault.balance();
      const depositAmount = userBalance;
      await vault.connect(wantHolder).deposit(depositAmount);

      const newVaultBalance = await vault.balance();
      const newUserBalance = await want.balanceOf(wantHolderAddr);
      const allowedInaccuracy = depositAmount.div(200);
      expect(depositAmount).to.be.closeTo(newVaultBalance, allowedInaccuracy);
    });

    xit('should allow withdrawals', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = userBalance;
      await vault.connect(wantHolder).deposit(depositAmount);

      await vault.connect(wantHolder).withdrawAll();
      const newUserVaultBalance = await vault.balanceOf(wantHolderAddr);
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);
      console.log(`userBalance: ${userBalance}`);
      console.log(`userBalanceAfterWithdraw: ${userBalanceAfterWithdraw}`);

      const smallDifference = userBalance.div(1000);
      console.log(`Difference: ${userBalance.sub(userBalanceAfterWithdraw)}`);
      const isSmallBalanceDifference = userBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    xit('should allow small withdrawal', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.000001', 8);
      await vault.connect(wantHolder).deposit(depositAmount);

      await vault.connect(wantHolder).withdrawAll();
      const newUserVaultBalance = await vault.balanceOf(wantHolderAddr);
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);

      const smallDifference = userBalance.div(10000);
      console.log(userBalance.sub(userBalanceAfterWithdraw));
      const isSmallBalanceDifference = userBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    xit('should be able to harvest', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      await vault.connect(wantHolder).deposit(userBalance);
      await strategy.harvest();
    });

    xit('should provide yield', async function () {
      const timeToSkip = 3600;
      const initialUserBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = initialUserBalance;

      await vault.connect(wantHolder).deposit(depositAmount);
      const initialVaultBalance = await vault.balance();
      await rebalance(strategy);

      await strategy.updateHarvestLogCadence(1);

      const numHarvests = 5;
      for (let i = 0; i < numHarvests; i++) {
        await moveTimeForward(timeToSkip);
        await moveBlocksForward(100);
        await strategy.harvest();
      }

      const finalVaultBalance = await vault.balance();
      expect(finalVaultBalance).to.be.gt(initialVaultBalance);

      const averageAPR = await strategy.averageAPRAcrossLastNHarvests(numHarvests);
      console.log(`Average APR across ${numHarvests} harvests is ${averageAPR} basis points.`);
    });
  });
  describe('Strategy', function () {
    xit('should be able to pause and unpause', async function () {
      await strategy.pause();
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = userBalance;
      await expect(vault.connect(wantHolder).deposit(depositAmount)).to.be.reverted;

      await strategy.unpause();
      await expect(vault.connect(wantHolder).deposit(depositAmount)).to.not.be.reverted;
    });

    xit('should be able to panic', async function () {
      const depositAmount = toWantUnit('0.0007', 8);
      await vault.connect(wantHolder).deposit(depositAmount);
      const vaultBalance = await vault.balance();
      const strategyBalance = await strategy.balanceOf();
      await strategy.panic();

      const wantStratBalance = await want.balanceOf(strategy.address);
      const allowedImprecision = toWantUnit('0.000000001');
      expect(strategyBalance).to.be.closeTo(wantStratBalance, allowedImprecision);
    });

    xit('should be able to retire strategy', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = userBalance;
      await vault.connect(wantHolder).deposit(depositAmount);
      const vaultBalance = await vault.balance();
      const strategyBalance = await strategy.balanceOf();
      expect(vaultBalance).to.equal(strategyBalance);

      await strategy.reclaimWant();

      await expect(strategy.retireStrat()).to.not.be.reverted;
      const newVaultBalance = await vault.balance();
      const newStrategyBalance = await strategy.balanceOf();
      const allowedImprecision = toWantUnit('0.001');
      expect(newVaultBalance).to.be.closeTo(vaultBalance, allowedImprecision);
      expect(newStrategyBalance).to.be.lt(allowedImprecision);
    });

    xit('should be able to retire strategy with no balance', async function () {
      await expect(strategy.retireStrat()).to.not.be.reverted;
    });

    xit('should be able to estimate harvest', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      await vault.connect(wantHolder).deposit(userBalance);
      await moveBlocksForward(100);
      await strategy.harvest();
      await moveBlocksForward(100);
      await strategy.updateExchangeRates();
      const [profit, callFeeToUser] = await strategy.estimateHarvest();
      console.log(`profit: ${profit}`);
      const hasProfit = profit.gt(0);
      const hasCallFee = callFeeToUser.gt(0);
      expect(hasProfit).to.equal(true);
      expect(hasCallFee).to.equal(true);
    });
    it('should be able to remove a pool', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = userBalance;
      await vault.connect(wantHolder).deposit(depositAmount);
      await strategy.reclaimWant();
      await rebalance(strategy);
      const poolBalances = await strategy.getPoolBalances();
      console.log(poolBalances[0].allocation);
      // Make sure pool has a balance to begin with to test withdraw + remove pool
      expect(poolBalances[0].allocation.gt(0)).to.equal(true);
      const poolAddress = poolBalances[0].poolAddress;
      await strategy.withdrawFromPool(poolAddress);
      const newBalance = await strategy.wantSuppliedToPool(poolAddress);
      console.log(`newBalance: ${newBalance}`);
      await expect(strategy.removeUsedPool(poolAddress)).to.not.be.reverted;
    });
  });
});
