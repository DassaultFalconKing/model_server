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

    // Keep Gemma4 auto tool selection on the model's native protocol and let the
    // Gemma4 output parser extract calls afterwards. Constraining auto generation
    // after <|tool_call> is tempting, but real Gemma4 deployments have shown
    // constrained-decoding token collapse/pad-token failures, especially with
    // complex nested schemas used by coding agents. This also matches vLLM's
    // default auto-tool policy: unconstrained unless a tool explicitly opts into
    // strict schema enforcement. OVMS does not currently retain OpenAI per-tool
    // `strict`, so applying one global auto grammar is not equivalent and is less
    // compatible than native generation.
    if (!hardToolChoice) {
        return;
    }

    auto toolTags = buildToolTags(request);
    if (toolTags.empty()) {
        // Defensive only: hard-empty states were rejected above.
        return;
    }

    // Hard choices must remain fail-closed. Required/named selection is an API
    // contract, so constrain from generation position zero rather than allowing
    // prose before the model decides to emit a trigger.
    auto requiredTags = std::make_shared<ov::genai::StructuredOutputConfig::TagsWithSeparator>();
    requiredTags->tags = std::move(toolTags);
    requiredTags->separator = "";
    requiredTags->at_least_one = true;
    requiredTags->stop_after_first = false;
    ov::genai::StructuredOutputConfig::StructuralTag structuralTag = requiredTags;
    setStructuralTagsConfig(structuralTag);
}
}  // namespace ovms
