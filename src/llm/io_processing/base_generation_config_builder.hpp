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
#pragma once
#include <string>

#include <openvino/genai/generation_config.hpp>
#include <openvino/genai/tokenizer.hpp>
#include "../apis/openai_request.hpp"

namespace ovms {

enum DecodingMethod {
    STANDARD,
    FAST_DRAFT,
    EAGLE3,
    DFLASH,
    MTP,
    PROMPT_LOOKUP
};

class BaseGenerationConfigBuilder {
protected:
    ov::genai::GenerationConfig config;
    const bool enableToolGuidedGeneration;
    DecodingMethod decodingMethod;
    void setStructuralTagsConfig(const ov::genai::StructuredOutputConfig::StructuralTag& structuralTag);

public:
    BaseGenerationConfigBuilder() = delete;
    explicit BaseGenerationConfigBuilder(const ov::genai::GenerationConfig& baseConfig, bool enableToolGuidedGeneration, DecodingMethod decodingMethod) :
        config(baseConfig),
        enableToolGuidedGeneration(enableToolGuidedGeneration),
        decodingMethod(decodingMethod) {}
    virtual ~BaseGenerationConfigBuilder() = default;

    ov::genai::GenerationConfig& getConfig() { return config; }
    void adjustConfigForDecodingMethod();
    void addStopString(const std::string& decodedStopString);
    void validateStructuredOutputConfig(ov::genai::Tokenizer& tokenizer);
    void unsetStructuredOutputConfig();

    // Model-specific policy for structured-output validation failures. The generic
    // serving path historically falls back to unguided generation; builders that
    // represent a hard API contract may override this to keep the grammar fail-closed.
    virtual bool shouldPreserveStructuredOutputOnValidationFailure() const { return false; }

    virtual void parseConfigFromRequest(const OpenAIRequest& request);
};
}  // namespace ovms
