// Copyright 2026 Intel Corporation
// Licensed under the Apache License, Version 2.0.

#include <string>

#include <gtest/gtest.h>
#include <openvino/genai/chat_history.hpp>

#include "src/llm/io_processing/chat_template/analyzer.hpp"
#include "src/llm/io_processing/input_processors/chat_template_adapter.hpp"

using namespace ovms;

namespace {

ov::genai::ChatHistory buildHistory(const std::string& messagesJson) {
    ov::genai::ChatHistory history;
    auto container = ov::genai::JsonContainer::from_json_string(messagesJson);
    for (size_t i = 0; i < container.size(); ++i) {
        history.push_back(container[i]);
    }
    return history;
}

}  // namespace

TEST(Gemma4ChatTemplateOverlayContractTest, ComposesUpstreamResponseFieldAndMappingCapabilities) {
    const std::string templateSource = R"(
        {{ '<|tool_call>call:' }}
        {% if response is mapping %}{{ response }}{% endif %}
    )";

    const auto result = ChatTemplateAnalyzer::analyze(templateSource);
    ASSERT_TRUE(result.detectedToolParser.has_value());
    EXPECT_EQ(result.detectedToolParser.value(), "gemma4");
    EXPECT_TRUE(result.caps.supportsToolCalls);
    EXPECT_TRUE(result.caps.supportsResponseFieldInToolDefinition);
    EXPECT_TRUE(result.caps.parseToolResponseJsonContent);
}

TEST(Gemma4ChatTemplateOverlayContractTest, GooglePartsIterationKeepsToolContentString) {
    const std::string templateSource = R"(
        {{ '<|tool_call>call:' }}
        {% if response is mapping %}{{ response }}{% endif %}
        {% for part in message.content %}{{ part.get('type') }}{% endfor %}
    )";

    const auto result = ChatTemplateAnalyzer::analyze(templateSource);
    ASSERT_TRUE(result.detectedToolParser.has_value());
    EXPECT_EQ(result.detectedToolParser.value(), "gemma4");
    EXPECT_TRUE(result.caps.supportsResponseFieldInToolDefinition);
    EXPECT_FALSE(result.caps.parseToolResponseJsonContent);
}

TEST(Gemma4ChatTemplateOverlayContractTest, MappingConversionPreservesOpaqueNestedToolResult) {
    static const std::string expectedSha = "798e99e04d53fba2b1c87bd6b88260f0d6c3ca83";
    auto history = buildHistory(R"([
        {"role":"tool","tool_call_id":"call_repo",
         "content":"{\"head_sha\":\"798e99e04d53fba2b1c87bd6b88260f0d6c3ca83\",\"nested\":{\"dirty\":true}}"}
    ])");

    chat_template_adapter::toolResponseJsonContentToObjectHistory(history);

    ASSERT_TRUE(history[0]["content"].is_object());
    EXPECT_EQ(history[0]["content"]["head_sha"].get_string(), expectedSha);
    EXPECT_EQ(history[0]["content"]["nested"].to_json_string(), R"({"dirty":true})");
}

TEST(Gemma4ChatTemplateOverlayContractTest, MappingConversionLeavesArraysScalarsAndNonJsonUntouched) {
    for (const std::string content : {"[1,2,3]", "42", "true", "not json"}) {
        auto history = buildHistory(std::string("[{\"role\":\"tool\",\"content\":\"") + content + "\"}]");
        chat_template_adapter::toolResponseJsonContentToObjectHistory(history);
        ASSERT_TRUE(history[0]["content"].is_string());
        EXPECT_EQ(history[0]["content"].get_string(), content);
    }
}
