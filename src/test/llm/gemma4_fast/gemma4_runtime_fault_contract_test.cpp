//*****************************************************************************
// Copyright 2026 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//*****************************************************************************

#include <gtest/gtest.h>

#include "../../../llm/language_model/continuous_batching/runtime_fault.hpp"

namespace ovms {
namespace {

TEST(Gemma4RuntimeFaultContract, ClOutOfResourcesIsContextFatal) {
    EXPECT_EQ(classifyRuntimeFault("[GPU] CL_OUT_OF_RESOURCES exception"), RuntimeFaultClass::GPU_CONTEXT_FATAL);
}

TEST(Gemma4RuntimeFaultContract, ClFinishFailureIsContextFatal) {
    EXPECT_EQ(classifyRuntimeFault("OpenCL clFinish failed with error -5"), RuntimeFaultClass::GPU_CONTEXT_FATAL);
}

TEST(Gemma4RuntimeFaultContract, DeviceLossIsContextFatal) {
    EXPECT_EQ(classifyRuntimeFault("GPU device lost during execution"), RuntimeFaultClass::GPU_CONTEXT_FATAL);
}

TEST(Gemma4RuntimeFaultContract, OneDnnPrimitiveFailureIsAmbiguousExecutionFailure) {
    EXPECT_EQ(classifyRuntimeFault("could not execute a primitive"), RuntimeFaultClass::GPU_EXECUTION_FAILURE);
    EXPECT_EQ(classifyRuntimeFault("primitive_onednn_base.h:559"), RuntimeFaultClass::GPU_EXECUTION_FAILURE);
}

TEST(Gemma4RuntimeFaultContract, ParserOrRequestErrorsAreNotRuntimeFaults) {
    EXPECT_EQ(classifyRuntimeFault("invalid tool call arguments"), RuntimeFaultClass::NONE);
    EXPECT_EQ(classifyRuntimeFault("finish_reason=length"), RuntimeFaultClass::NONE);
    EXPECT_EQ(classifyRuntimeFault("invalid request max_tokens"), RuntimeFaultClass::NONE);
}

TEST(Gemma4RuntimeFaultContract, Gemma4PolicyIsExplicitAndNarrow) {
    EXPECT_TRUE(isGemma4CircuitBreakerEnabled("gemma4"));
    EXPECT_TRUE(isGemma4CircuitBreakerEnabled("GEMMA4"));
    EXPECT_FALSE(isGemma4CircuitBreakerEnabled(""));
    EXPECT_FALSE(isGemma4CircuitBreakerEnabled("qwen3"));
}

TEST(Gemma4RuntimeFaultContract, ContextFatalIsContainedForEveryModel) {
    EXPECT_TRUE(shouldContainRuntimeFault(RuntimeFaultClass::GPU_CONTEXT_FATAL, false));
    EXPECT_TRUE(shouldContainRuntimeFault(RuntimeFaultClass::GPU_CONTEXT_FATAL, true));
}

TEST(Gemma4RuntimeFaultContract, AmbiguousPrimitiveFailureIsContainedOnlyByGemma4Policy) {
    EXPECT_FALSE(shouldContainRuntimeFault(RuntimeFaultClass::GPU_EXECUTION_FAILURE, false));
    EXPECT_TRUE(shouldContainRuntimeFault(RuntimeFaultClass::GPU_EXECUTION_FAILURE, true));
}

TEST(Gemma4RuntimeFaultContract, FaultStateTransitionsAreMonotonic) {
    RuntimeFaultState state;
    EXPECT_EQ(state.health(), ExecutorHealth::HEALTHY);
    EXPECT_FALSE(state.isFaulted());

    state.trip(RuntimeFaultClass::GPU_EXECUTION_FAILURE, "primitive failed");
    EXPECT_EQ(state.health(), ExecutorHealth::TRIPPED);
    EXPECT_EQ(state.faultClass(), RuntimeFaultClass::GPU_EXECUTION_FAILURE);
    EXPECT_EQ(state.reason(), "primitive failed");
    EXPECT_TRUE(state.isFaulted());

    state.requireRecovery();
    EXPECT_EQ(state.health(), ExecutorHealth::RECOVERY_REQUIRED);

    // Fault state is fail-closed: a later weaker signal must not clear or downgrade it.
    state.trip(RuntimeFaultClass::NONE, "not a fault");
    EXPECT_EQ(state.health(), ExecutorHealth::RECOVERY_REQUIRED);
    EXPECT_EQ(state.faultClass(), RuntimeFaultClass::GPU_EXECUTION_FAILURE);
}

}  // namespace
}  // namespace ovms
