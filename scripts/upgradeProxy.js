async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyLendingOptimizer');
  const stratContract = await hre.upgrades.upgradeProxy('0x34E4A4670E26A9BB3DD0Ec0909914C8d95B5B0B1', stratFactory, {
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
