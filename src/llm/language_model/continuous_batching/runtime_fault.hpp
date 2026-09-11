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

#pragma once

#include <algorithm>
#include <atomic>
#include <cctype>
#include <mutex>
#include <string>
#include <string_view>

namespace ovms {

enum class RuntimeFaultClass {
    NONE = 0,
    GPU_EXECUTION_FAILURE = 1,
    GPU_CONTEXT_FATAL = 2,
};

enum class ExecutorHealth {
    HEALTHY = 0,
    TRIPPED = 1,
    RECOVERY_REQUIRED = 2,
};

inline std::string normalizeRuntimeFaultText(std::string_view message) {
    std::string normalized(message);
    std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return normalized;
}

inline RuntimeFaultClass classifyRuntimeFault(std::string_view message) {
    const std::string normalized = normalizeRuntimeFaultText(message);

    if (normalized.find("cl_out_of_resources") != std::string::npos ||
        normalized.find("clfinish") != std::string::npos ||
        normalized.find("cl_finish") != std::string::npos ||
        normalized.find("device lost") != std::string::npos ||
        normalized.find("cl_device_not_available") != std::string::npos) {
        return RuntimeFaultClass::GPU_CONTEXT_FATAL;
    }

    if (normalized.find("could not execute a primitive") != std::string::npos ||
        normalized.find("primitive_onednn_base") != std::string::npos) {
        return RuntimeFaultClass::GPU_EXECUTION_FAILURE;
    }

    return RuntimeFaultClass::NONE;
}

inline bool isGemma4CircuitBreakerEnabled(std::string_view toolParserName) {
    return normalizeRuntimeFaultText(toolParserName) == "gemma4";
}

inline bool shouldContainRuntimeFault(RuntimeFaultClass faultClass, bool gemma4CircuitBreakerEnabled) {
    if (faultClass == RuntimeFaultClass::GPU_CONTEXT_FATAL) {
        return true;
    }
    return faultClass == RuntimeFaultClass::GPU_EXECUTION_FAILURE && gemma4CircuitBreakerEnabled;
}

class RuntimeFaultState {
    std::atomic<ExecutorHealth> executorHealth{ExecutorHealth::HEALTHY};
    std::atomic<RuntimeFaultClass> runtimeFaultClass{RuntimeFaultClass::NONE};
    mutable std::mutex reasonMutex;
    std::string faultReason;

public:
    void trip(RuntimeFaultClass faultClass, std::string reason) {
        if (faultClass == RuntimeFaultClass::NONE || executorHealth.load(std::memory_order_acquire) != ExecutorHealth::HEALTHY) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(reasonMutex);
            faultReason = std::move(reason);
        }
        runtimeFaultClass.store(faultClass, std::memory_order_release);
        executorHealth.store(ExecutorHealth::TRIPPED, std::memory_order_release);
    }

    void requireRecovery() {
        if (executorHealth.load(std::memory_order_acquire) != ExecutorHealth::HEALTHY) {
            executorHealth.store(ExecutorHealth::RECOVERY_REQUIRED, std::memory_order_release);
        }
    }

    bool isFaulted() const {
        return executorHealth.load(std::memory_order_acquire) != ExecutorHealth::HEALTHY;
    }

    ExecutorHealth health() const {
        return executorHealth.load(std::memory_order_acquire);
    }

    RuntimeFaultClass faultClass() const {
        return runtimeFaultClass.load(std::memory_order_acquire);
    }

    std::string reason() const {
        std::lock_guard<std::mutex> lock(reasonMutex);
        return faultReason;
    }
};

}  // namespace ovms
