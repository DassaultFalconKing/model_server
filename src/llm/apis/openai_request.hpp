//*****************************************************************************
// Copyright 2025 Intel Corporation
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

// Type that holds vector of pairs where first element is chat turn index and second is image tensor
// this way we store information about which image is associated with which chat turn
#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <set>
#include <utility>
#include <vector>

#include <openvino/runtime/tensor.hpp>
#include <openvino/genai/tokenizer.hpp>

#include "src/port/rapidjson_document.hpp"

#include "tool_schema_wrapper.hpp"

namespace ovms {
struct StreamOptions {
    bool includeUsage = false;
};
// Class that maps OpenAI request content.
struct OpenAIRequest {
    ov::genai::ChatHistory chatHistory;
    std::optional<std::string> prompt{std::nullopt};
    bool stream{false};
    StreamOptions streamOptions;
    std::string model;
    std::optional<int> maxTokens{std::nullopt};
    bool logprobs{false};
    int logprobschat{0};
    bool echo{false};
    std::optional<bool> ignoreEOS{std::nullopt};
    std::optional<std::set<std::string>> stop{std::nullopt};
    std::optional<bool> includeStopStrInOutput{std::nullopt};
    std::optional<int> numReturnSequences{std::nullopt};
    std::optional<float> temperature{std::nullopt};
    std::optional<float> topP{std::nullopt};
    std::optional<float> minP{std::nullopt};
    std::optional<int> topK{std::nullopt};
    std::optional<uint32_t> seed{std::nullopt};
    std::optional<float> frequencyPenalty{std::nullopt};
    std::optional<float> presencePenalty{std::nullopt};
    std::optional<float> repetitionPenalty{std::nullopt};
    std::optional<int> bestOf{std::nullopt};
    std::optional<float> lengthPenalty{std::nullopt};

    std::optional<int> numAssistantTokens{std::nullopt};
    std::optional<float> assistantConfidenceThreshold{std::nullopt};
    std::optional<int> maxNgramSize{std::nullopt};
    std::optional<size_t> branchingFactor{std::nullopt};
    std::optional<size_t> treeDepth{std::nullopt};

    std::optional<uint32_t> maxModelLength;

    std::optional<std::string> responseFormat{std::nullopt};
    ToolsSchemas_t toolNameSchemaMap;
    std::string toolChoice;
    // OpenAI-compatible default is true when omitted. This policy is consumed by
    // Gemma4 structural generation to decide whether later tool triggers remain legal.
    bool parallelToolCalls{true};

    bool skipSpecialTokens{true};

    enum class AudioFormat { WAV,
        PCM16 };
    static constexpr AudioFormat DEFAULT_AUDIO_FORMAT = AudioFormat::WAV;
    bool audioOutputRequested{false};
    bool textOutputRequested{true};
    std::string audioVoice;
    AudioFormat audioFormat{DEFAULT_AUDIO_FORMAT};
    static constexpr size_t DEFAULT_AUDIO_CHUNK_FRAMES = 4;
    size_t audioChunkFrames{DEFAULT_AUDIO_CHUNK_FRAMES};

    OpenAIRequest() = default;
    ~OpenAIRequest() = default;
};
}  // namespace ovms
