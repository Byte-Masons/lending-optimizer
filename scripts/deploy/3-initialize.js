async function main() {
  const vaultAddress = '0x297c228B119f0d185a5D68a881D6E3637C008b5b';
  const strategyAddress = '0x16c38c642f3126eC9E46148008E42dBF61cE730b';

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
