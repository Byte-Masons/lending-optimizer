async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyLendingOptimizer');
  const stratContract = await hre.upgrades.upgradeProxy('0x7D2F7B4001322318050Fc11aD3d1dda5d2c82d38', stratFactory, {
    timeout: 0,
  });
  console.log('Strategy upgraded!');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
