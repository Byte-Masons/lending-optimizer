async function main() {
  const stratFactory = await ethers.getContractFactory('ReaperStrategyLendingOptimizer');
  const strategyAddress = '0x8858C3FEF08f66db12983893c326E3E46c94c539';
  const strategy = stratFactory.attach(strategyAddress);
  const options = {gasPrice: 1000000000000};
  // await strategy.reclaimWant(options);
  // console.log('reclaimed want');
  const poolsToRemove = [
    //2, 20, 788517714455024, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 7, 1, 3, 5, 3, 1, 1, 6, 1, 3, 1, 1
    //'0xcde8e796038373ff030b56c9717757d293b703eb',
    '0x5990ddc40b63d90d3b783207069f5b9a8b661c1c',
    '0x7e9a1c333cab2081583b74964ff82696706bba8b',
    '0xcb61e66a8a6a62afb14858965d887952984587b9',
    '0x133e827dfcd415213584363f95b1c686be5dc27e',
    '0x2d8c65844018e0b46f58ce8c70e01f1f21a8eac5',
    '0x577bccf20972fd13bf4749df12a7616be9c8b249',
    '0x5516fe3b0f0d620496b784c43877de6d0d722c28',
    '0x2e5d02fb402670d76c3f31fb23e8f396e73d5252',
    '0xd05f23002f6d09cf7b643b69f171cc2a3eacd0b3',
    '0x4f04f1d467de9172a88c67f845f08d6961f39e6c',
    '0x84069262f02a95f5fe8f9f2889003f256c3c5849',
    '0xa7e140cadd68aeed5874b3417741c0176f85ace4',
    '0x7078183318adb7088f97d5884f35b1321a34224b',
  ];
  await strategy.removeUsedPools(poolsToRemove, options);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
