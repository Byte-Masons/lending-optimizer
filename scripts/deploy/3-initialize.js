async function main() {
  const vaultAddress = '0x7A688CFc89BAFA29f5027EE457454bec919cAEf2';
  const strategyAddress = '0x34E4A4670E26A9BB3DD0Ec0909914C8d95B5B0B1';

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
