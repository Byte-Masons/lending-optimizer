async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyLendingOptimizer');
  const stratContract = await hre.upgrades.upgradeProxy('0x235A76b2747728Ec5CBBc36642dc27308C9189be', stratFactory, {
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
