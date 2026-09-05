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

#include "generation_config_builder.hpp"

#include <memory>
#include <stdexcept>
#include <utility>

#include "src/port/rapidjson_document.hpp"

namespace ovms {
namespace {

bool isNamedToolChoice(const std::string& toolChoice) {
    return !toolChoice.empty() && toolChoice != "auto" && toolChoice != "none" && toolChoice != "required";
}

void validateToolSchema(const std::string& toolName, const ToolSchemaWrapper& toolSchemaWrapper) {
    rapidjson::Document schema;
    schema.Parse(toolSchemaWrapper.stringRepr.c_str());
    if (schema.HasParseError() || !schema.IsObject()) {
        throw std::invalid_argument("Gemma4 guided tool schema for '" + toolName + "' must be a valid JSON object");
    }
}

ov::genai::StructuredOutputConfig::Tag buildToolTag(const std::string& toolName, const ToolSchemaWrapper& toolSchemaWrapper) {
    validateToolSchema(toolName, toolSchemaWrapper);

    ov::genai::StructuredOutputConfig::Tag tag;
    tag.begin = "<|tool_call>call:" + toolName;
    tag.content = ov::genai::StructuredOutputConfig::JSONSchema(toolSchemaWrapper.stringRepr);
    tag.end = "<tool_call|>";
    return tag;
}

}  // namespace

bool Gemma4GenerationConfigBuilder::isHardToolChoice(const std::string& toolChoice) {
    return toolChoice == "required" || isNamedToolChoice(toolChoice);
}

std::vector<ov::genai::StructuredOutputConfig::Tag> Gemma4GenerationConfigBuilder::buildToolTags(const OpenAIRequest& request) {
    std::vector<ov::genai::StructuredOutputConfig::Tag> tags;

    // OpenAIApiHandler currently pre-filters named choices, but the generation
    // builder owns the final hard-generation contract. Keep that contract true
    // even for callers that construct OpenAIRequest directly or fail to filter.
    if (isNamedToolChoice(request.toolChoice)) {
        const auto it = request.toolNameSchemaMap.find(request.toolChoice);
        if (it == request.toolNameSchemaMap.end()) {
            throw std::invalid_argument("Gemma4 named tool_choice references an unavailable tool: " + request.toolChoice);
        }
        tags.reserve(1);
        tags.push_back(buildToolTag(it->first, it->second));
        return tags;
    }

    tags.reserve(request.toolNameSchemaMap.size());
    for (const auto& [toolName, toolSchemaWrapper] : request.toolNameSchemaMap) {
        tags.push_back(buildToolTag(toolName, toolSchemaWrapper));
    }
    return tags;
}

void Gemma4GenerationConfigBuilder::parseConfigFromRequest(const OpenAIRequest& request) {
    BaseGenerationConfigBuilder::parseConfigFromRequest(request);

    const bool hardToolChoice = isHardToolChoice(request.toolChoice);

    // A hard OpenAI tool choice cannot degrade to unconstrained generation just
    // because request preparation left us without an enforceable schema.
    if (hardToolChoice && request.toolNameSchemaMap.empty()) {
        throw std::invalid_argument("Gemma4 hard tool_choice requires at least one available tool schema");
    }

    // GenAI exposes one structural_tags_config. Silently overwriting a user
    // response_format with tool grammar (or vice versa) would satisfy neither API
    // contract reliably, so reject the unsupported combination explicitly.
    if (request.responseFormat.has_value() && request.toolChoice != "none" && !request.toolNameSchemaMap.empty()) {
        throw std::invalid_argument("Gemma4 response_format cannot be combined with active tool generation constraints");
    }

    if (request.toolNameSchemaMap.empty() || request.toolChoice == "none") {
        return;
    }

    if (!hardToolChoice && !enableToolGuidedGeneration) {
        return;
    }

    auto toolTags = buildToolTags(request);
    if (toolTags.empty()) {
        // Defensive only: all hard-empty states were rejected above and optional
        // generation should not install an empty structural grammar.
        return;
    }

    if (hardToolChoice) {
        // TriggeredTags still permits prose before Gemma chooses to emit the
        // trigger. Hard choices must constrain from generation position zero.
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
}  // namespace ovms
