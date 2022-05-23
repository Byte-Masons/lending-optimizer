async function main() {
  const vaultAddress = '0xCdb3eb37BD298e57009869D9Be5402b8885aAe9D';
  const strategyAddress = '0x0D5b10107067A4AF13ae795Ea6c83a808d394b74';

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
