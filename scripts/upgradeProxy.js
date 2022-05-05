async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyLendingOptimizer');
  const stratContract = await hre.upgrades.upgradeProxy('0x8858C3FEF08f66db12983893c326E3E46c94c539', stratFactory, {
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
