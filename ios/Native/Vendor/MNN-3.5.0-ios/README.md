# MNN 3.5.0 iOS Core

This directory contains the official Alibaba MNN iOS package that matches the
Android-side MNN 3.5.0 runtime used by this repository.

Source:

```text
https://github.com/alibaba/MNN/releases/download/3.5.0/mnn_3.5.0_ios_armv82_cpu_metal_coreml.zip
```

SHA256:

```text
fd9b6c5769718286f07ff300897c72ff6511a1d2a25ef79b3b2f8b2b3313281a  mnn_3.5.0_ios_armv82_cpu_metal_coreml.zip
d1c1bb805529e90e6267887720847b6622cd9224cf00c4f8d080b62721b74649  MNN.framework/MNN
```

The package provides an iOS `arm64` static `MNN.framework` with the core
`MNN::Interpreter` and `MNN::Tensor` symbols required to build the SilverCare
iOS wrapper. It is not, by itself, the final runtime loaded by the app. Final
Android parity still requires a `SilverCareMNNRuntime` artifact exporting the C
ABI documented in `ios/Native/SilverCareMNNRuntimeABI.h`.
