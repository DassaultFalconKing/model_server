//*****************************************************************************
// Copyright 2024 Intel Corporation
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
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

#include <openvino/genai/continuous_batching_pipeline.hpp>

#include "../../../logging.hpp"
#include "../../../profiler.hpp"

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

inline const char* runtimeFaultClassName(RuntimeFaultClass faultClass) {
    switch (faultClass) {
    case RuntimeFaultClass::GPU_CONTEXT_FATAL:
        return "GPU_CONTEXT_FATAL";
    case RuntimeFaultClass::GPU_EXECUTION_FAILURE:
        return "GPU_EXECUTION_FAILURE";
    case RuntimeFaultClass::NONE:
    default:
        return "NONE";
    }
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

struct LLMExecutor {
    bool isDynamicKVCache;
    // For logging purposes we could have more information about graph and node here
    std::mutex mutex;
    std::condition_variable cv;
    std::shared_ptr<ov::genai::ContinuousBatchingPipeline> pipe = nullptr;

    LLMExecutor(std::shared_ptr<ov::genai::ContinuousBatchingPipeline> pipe, bool isDynamicKVCacheSet = false) {
        this->pipe = std::move(pipe);
        this->isDynamicKVCache = isDynamicKVCacheSet;
    }

    bool hasRequests() {
        return (pipe->has_non_finished_requests());
    }

    void step() {
        OVMS_PROFILE_FUNCTION();
        pipe->step();
    }

    void waitForRequests(std::atomic<bool>* receivedEndSignal) {
        std::unique_lock<std::mutex> lock(mutex);
        cv.wait(lock, [this, receivedEndSignal] { return (pipe->has_non_finished_requests() || *receivedEndSignal); });
    }

    void notify() {
        std::unique_lock<std::mutex> lock(mutex);
        cv.notify_one();
    }

    std::string formatCacheInfo(float cacheUsage, size_t cacheBytes, bool isCacheDynamic) {
        std::ostringstream oss;
        oss << std::fixed << std::setprecision(1);
        if (isCacheDynamic) {
            oss << "type: dynamic, cache usage: " << cacheUsage << "% of " << formatBytes(cacheBytes);
        } else {
            oss << "type: static, cache usage: " << cacheUsage << "% of " << formatBytes(cacheBytes);
        }

        return oss.str();
    }

    std::string formatBytes(size_t bytes) {
        const double KB = 1024.0;
        const double MB = KB * 1024.0;
        const double GB = MB * 1024.0;
        const double TB = GB * 1024.0;

        std::ostringstream oss;
        oss << std::fixed << std::setprecision(1);

        if (bytes >= TB)
            oss << (bytes / TB) << " TB";
        else if (bytes >= GB)
            oss << (bytes / GB) << " GB";
        else if (bytes >= MB)
            oss << (bytes / MB) << " MB";
        else if (bytes >= KB)
            oss << (bytes / KB) << " KB";
        else
            oss << bytes << " B";

        return oss.str();
    }

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
    void printMetrics() {
        ov::genai::PipelineMetrics metrics = pipe->get_metrics();
        SPDLOG_LOGGER_INFO(llm_executor_logger, "All requests: {}; Scheduled requests: {}; Cache {};",
            metrics.requests, metrics.scheduled_requests, formatCacheInfo(metrics.cache_usage, metrics.kv_cache_size_in_bytes, this->isDynamicKVCache));
    }
};
#pragma GCC diagnostic pop

class LLMExecutorWrapper {
    LLMExecutor llmExecutor;
    RuntimeFaultState runtimeFaultState;
    std::atomic<bool> gemma4CircuitBreakerEnabled{false};
    std::thread llmExecutorThread;
    std::atomic<bool> finishExecutorThread = false;

    static void run(LLMExecutor* llmExecutor, RuntimeFaultState* runtimeFaultState, std::atomic<bool>* gemma4CircuitBreakerEnabled, std::atomic<bool>* receivedEndSignal) {
        const uint8_t printMetricsEveryNumberOfSteps = 10;
        uint8_t stepCounter = 0;
        while (!(*receivedEndSignal)) {
            try {
                if (stepCounter == printMetricsEveryNumberOfSteps) {
                    llmExecutor->printMetrics();
                    stepCounter = 0;
                }
                if (llmExecutor->hasRequests()) {
                    stepCounter++;
                    llmExecutor->step();
                } else {
                    SPDLOG_LOGGER_INFO(llm_executor_logger, "All requests: {}; Scheduled requests: {};", 0, 0);
                    llmExecutor->waitForRequests(receivedEndSignal);
                }
            } catch (const std::exception& e) {
                const RuntimeFaultClass faultClass = classifyRuntimeFault(e.what());
                const bool gemma4BreakerActive = gemma4CircuitBreakerEnabled->load(std::memory_order_acquire);
                if (shouldContainRuntimeFault(faultClass, gemma4BreakerActive)) {
                    runtimeFaultState->trip(faultClass, e.what());
                    runtimeFaultState->requireRecovery();
                    SPDLOG_LOGGER_ERROR(llm_executor_logger,
                        "Contained LLM executor runtime fault: class={}; gemma4_breaker={}; executor quarantined; model reload/recreation required. Original error: {}",
                        runtimeFaultClassName(faultClass), gemma4BreakerActive, e.what());
                    return;
                }
                SPDLOG_LOGGER_ERROR(llm_executor_logger, "Error occurred in LLM executor: {}.", e.what());
                exit(1);
            }
        }
    }

public:
    LLMExecutorWrapper(std::shared_ptr<ov::genai::ContinuousBatchingPipeline> pipe, bool isDynamicKVCache = false) :
        llmExecutor(std::move(pipe), isDynamicKVCache) {
        llmExecutorThread = std::thread(LLMExecutorWrapper::run, &llmExecutor, &runtimeFaultState, &gemma4CircuitBreakerEnabled, &finishExecutorThread);
    }

    ~LLMExecutorWrapper() {
        finishExecutorThread = true;
        llmExecutor.notify();
        llmExecutorThread.join();
    }

    void setGemma4CircuitBreakerEnabled(bool enabled) {
        gemma4CircuitBreakerEnabled.store(enabled, std::memory_order_release);
    }

    void notifyNewRequestArrived() {
        if (!runtimeFaultState.isFaulted()) {
            llmExecutor.notify();
        }
    }

    bool isFaulted() const {
        return runtimeFaultState.isFaulted();
    }

    ExecutorHealth health() const {
        return runtimeFaultState.health();
    }

    RuntimeFaultClass faultClass() const {
        return runtimeFaultState.faultClass();
    }

    std::string faultReason() const {
        return runtimeFaultState.reason();
    }
};

}  // namespace ovms
