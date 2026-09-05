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
#include <iostream>
#include <memory>
#include <string>
#include <utility>
#include <vector>
#include <openvino/genai/generation_config.hpp>
#include <openvino/genai/tokenizer.hpp>
#include "base_generation_config_builder.hpp"
#include "phi4/generation_config_builder.hpp"
#include "llama3/generation_config_builder.hpp"
#include "hermes3/generation_config_builder.hpp"
#include "devstral/generation_config_builder.hpp"
#include "../apis/openai_request.hpp"
#include "../../logging.hpp"

namespace ovms {

// RC1-local Gemma4 builder. It intentionally lives in this already-built header so
// the 2026.4 RC1 port does not add a translation unit or mutate BUILD while we are
// proving the runtime contract on the exact 530dc63f lineage.
class Gemma4GenerationConfigBuilder : public BaseGenerationConfigBuilder {
    static bool isHardToolChoice(const std::string& toolChoice) {
        return toolChoice == "required" ||
            (!toolChoice.empty() && toolChoice != "auto" && toolChoice != "none");
    }

    static std::vector<ov::genai::StructuredOutputConfig::Tag> buildToolTags(const OpenAIRequest& request) {
        std::vector<ov::genai::StructuredOutputConfig::Tag> tags;
        tags.reserve(request.toolNameSchemaMap.size());
        for (const auto& [toolName, toolSchemaWrapper] : request.toolNameSchemaMap) {
            ov::genai::StructuredOutputConfig::Tag tag;
            tag.begin = "<|tool_call>call:" + toolName;
            tag.content = ov::genai::StructuredOutputConfig::JSONSchema(toolSchemaWrapper.stringRepr);
            tag.end = "<tool_call|>";
            tags.push_back(std::move(tag));
        }
        return tags;
    }

public:
    Gemma4GenerationConfigBuilder() = delete;
    explicit Gemma4GenerationConfigBuilder(const ov::genai::GenerationConfig& baseConfig, bool enableToolGuidedGeneration, DecodingMethod decodingMethod) :
        BaseGenerationConfigBuilder(baseConfig, enableToolGuidedGeneration, decodingMethod) {}

    void parseConfigFromRequest(const OpenAIRequest& request) override {
        BaseGenerationConfigBuilder::parseConfigFromRequest(request);

        if (request.toolNameSchemaMap.empty() || request.toolChoice == "none") {
            return;
        }

        const bool hardToolChoice = isHardToolChoice(request.toolChoice);
        if (!hardToolChoice && !enableToolGuidedGeneration) {
            return;
        }

        auto toolTags = buildToolTags(request);
        if (toolTags.empty()) {
            return;
        }

        if (hardToolChoice) {
            // A TriggeredTags grammar still permits prose before Gemma decides to emit
            // <|tool_call>. Hard choice must constrain from token zero instead.
            auto requiredTags = std::make_shared<ov::genai::StructuredOutputConfig::TagsWithSeparator>();
            requiredTags->tags = std::move(toolTags);
            requiredTags->separator = "";
            requiredTags->at_least_one = true;
            requiredTags->stop_after_first = false;
            ov::genai::StructuredOutputConfig::StructuralTag structuralTag = requiredTags;
            setStructuralTagsConfig(structuralTag);
            return;
        }

        auto triggeredTags = std::make_shared<ov::genai::StructuredOutputConfig::TriggeredTags>();
        triggeredTags->triggers.push_back("<|tool_call>");
        triggeredTags->tags = std::move(toolTags);
        triggeredTags->at_least_one = false;
        triggeredTags->stop_after_first = false;
        ov::genai::StructuredOutputConfig::StructuralTag structuralTag = triggeredTags;
        setStructuralTagsConfig(structuralTag);
    }
};

class GenerationConfigBuilder {
    std::unique_ptr<BaseGenerationConfigBuilder> builder_impl;

public:
    GenerationConfigBuilder() = delete;
    // Using tool parser name to select appropriate builder implementation to avoid introducing additional parameters. Might be insufficient in the future.
    explicit GenerationConfigBuilder(const ov::genai::GenerationConfig& baseConfig, std::string toolParserName, bool enableToolGuidedGeneration, DecodingMethod decodingMethod) {
        if (toolParserName == "llama3") {
            builder_impl = std::make_unique<Llama3GenerationConfigBuilder>(baseConfig, enableToolGuidedGeneration, decodingMethod);
        } else if (toolParserName == "qwen3") {
            // Qwen3 and Hermes3 share the same mechanism for generating tool calls, so we can use Hermes3GenerationConfigBuilder
            builder_impl = std::make_unique<Hermes3GenerationConfigBuilder>(baseConfig, enableToolGuidedGeneration, decodingMethod);
        } else if (toolParserName == "hermes3") {
            builder_impl = std::make_unique<Hermes3GenerationConfigBuilder>(baseConfig, enableToolGuidedGeneration, decodingMethod);
        } else if (toolParserName == "gemma4") {
            builder_impl = std::make_unique<Gemma4GenerationConfigBuilder>(baseConfig, enableToolGuidedGeneration, decodingMethod);
        } else if (toolParserName == "phi4") {
            builder_impl = std::make_unique<Phi4GenerationConfigBuilder>(baseConfig, enableToolGuidedGeneration, decodingMethod);
        } else if (toolParserName == "devstral") {
            builder_impl = std::make_unique<DevstralGenerationConfigBuilder>(baseConfig, enableToolGuidedGeneration, decodingMethod);
        } else {
            if (enableToolGuidedGeneration) {
                SPDLOG_LOGGER_DEBUG(llm_calculator_logger, "Option enable_tool_guided_generation is set, but will not be effective since no valid tool parser has been provided.");
            }
            builder_impl = std::make_unique<BaseGenerationConfigBuilder>(baseConfig, enableToolGuidedGeneration, decodingMethod);
        }
    }

    ov::genai::GenerationConfig& getConfig() {
        return builder_impl->getConfig();
    }

    void adjustConfigForDecodingMethod() {
        builder_impl->adjustConfigForDecodingMethod();
    }

    void validateStructuredOutputConfig(ov::genai::Tokenizer& tokenizer) {
        builder_impl->validateStructuredOutputConfig(tokenizer);
    }

    void unsetStructuredOutputConfig() {
        builder_impl->unsetStructuredOutputConfig();
    }

    void parseConfigFromRequest(const OpenAIRequest& request) {
        builder_impl->parseConfigFromRequest(request);
    }

    void addStopString(const std::string& decodedStopString) {
        builder_impl->addStopString(decodedStopString);
    }
};
}  // namespace ovms
