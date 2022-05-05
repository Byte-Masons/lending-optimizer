async function main() {
  const vaultAddress = '0xfefCAD80dE05Ff6Dc08Db7732f510682BA4e6778';
  const strategyAddress = '0x6CCD9FeabCF54d8781c1EA1C5D03B8B61F3Cecdd';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);

  await vault.initialize(strategyAddress);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
