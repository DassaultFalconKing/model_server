// Copyright 2026 Intel Corporation
// Licensed under the Apache License, Version 2.0.

#include <gtest/gtest.h>
#include <openvino/genai/llm_pipeline.hpp>
#include <string>
#include <variant>

#include "src/llm/io_processing/generation_config_builder.hpp"
#include "src/test/platform_utils.hpp"

using namespace ovms;
using Structured = ov::genai::StructuredOutputConfig;

namespace {
const std::string emptySchema = R"({"type":"object","properties":{},"additionalProperties":false})";
const std::string responseSchema = R"({"type":"structural_tag","format":{"type":"json_schema","json_schema":{"type":"object","properties":{"answer":{"type":"string"}}}}})";
const std::string openCodeQuestionSchema = R"({"type":"object","properties":{"questions":{"type":"array","items":{"type":"object","properties":{"question":{"type":"string"},"header":{"type":"string"},"options":{"type":"array","items":{"type":"object","properties":{"label":{"type":"string"},"description":{"type":"string"}},"required":["label","description"]}},"multiple":{"type":"boolean"},"custom":{"type":"boolean"}},"required":["question","header","options"]}}},"required":["questions"]})";

OpenAIRequest requestWithTools(const std::string& choice) {
    OpenAIRequest request;
    request.toolChoice = choice;
    request.toolNameSchemaMap.emplace("first", ToolSchemaWrapper{nullptr, emptySchema});
    request.toolNameSchemaMap.emplace("second", ToolSchemaWrapper{nullptr, emptySchema});
    return request;
}

template <typename T>
const T& grammar(const ov::genai::GenerationConfig& config) {
    return *std::get<std::shared_ptr<T>>(std::get<Structured::StructuralTag>(
        config.structured_output_config.value().structural_tags_config.value()));
}
}  // namespace

TEST(Gemma4GenerationContractTest, AbsentToolsAndNonePreserveResponseFormat) {
    for (bool guided : {false, true}) {
        for (bool response : {false, true}) {
            for (bool tools : {false, true}) {
                auto request = tools ? requestWithTools("none") : OpenAIRequest{};
                if (response)
                    request.responseFormat = responseSchema;
                GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
                builder.parseConfigFromRequest(request);
                EXPECT_EQ(builder.getConfig().structured_output_config.has_value(), response);
            }
        }
    }
}

TEST(Gemma4GenerationContractTest, TracksHardToolChoiceForValidationFallbackPolicy) {
    for (const std::string choice : {"", "none", "auto"}) {
        OpenAIRequest request;
        request.toolChoice = choice;
        GenerationConfigBuilder builder({}, "gemma4", false, STANDARD);
        builder.parseConfigFromRequest(request);
        EXPECT_FALSE(builder.hasHardToolChoice()) << choice;
    }
    for (const std::string choice : {"required", "second"}) {
        auto request = requestWithTools(choice);
        GenerationConfigBuilder builder({}, "gemma4", false, STANDARD);
        builder.parseConfigFromRequest(request);
        EXPECT_TRUE(builder.hasHardToolChoice()) << choice;
    }
}

TEST(Gemma4GenerationContractTest, HardChoiceCannotBeClearedAfterValidationFailure) {
    for (const std::string choice : {"required", "second"}) {
        auto request = requestWithTools(choice);
        GenerationConfigBuilder builder({}, "gemma4", false, STANDARD);
        builder.parseConfigFromRequest(request);
        ASSERT_TRUE(builder.getConfig().structured_output_config.has_value());
        EXPECT_NO_THROW(builder.unsetStructuredOutputConfig()) << choice;
        EXPECT_TRUE(builder.getConfig().structured_output_config.has_value()) << choice;
    }

    auto autoRequest = requestWithTools("auto");
    GenerationConfigBuilder autoBuilder({}, "gemma4", false, STANDARD);
    autoBuilder.parseConfigFromRequest(autoRequest);
    EXPECT_NO_THROW(autoBuilder.unsetStructuredOutputConfig());
    EXPECT_FALSE(autoBuilder.getConfig().structured_output_config.has_value());
}

TEST(Gemma4GenerationContractTest, AutoUsesNativeGemmaGenerationAndHardChoicesStayImmediateAndRepeatable) {
    for (bool guided : {false, true}) {
        for (const std::string choice : {"auto", "required", "second"}) {
            auto request = requestWithTools(choice);
            GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
            builder.parseConfigFromRequest(request);
            if (choice == "auto") {
                EXPECT_FALSE(builder.getConfig().structured_output_config)
                    << "Gemma4 auto tool choice must remain native/unconstrained";
            } else {
                const auto& tags = grammar<Structured::TagsWithSeparator>(builder.getConfig());
                EXPECT_TRUE(tags.at_least_one);
                EXPECT_FALSE(tags.stop_after_first);
                EXPECT_TRUE(tags.separator.empty());
                ASSERT_EQ(tags.tags.size(), choice == "second" ? 1u : 2u);
                if (choice == "second")
                    EXPECT_EQ(tags.tags[0].begin, "<|tool_call>call:second");
            }
        }
    }
}

TEST(Gemma4GenerationContractTest, OpenCodeQuestionSchemaDoesNotConstrainAutoButRemainsEnforcedForRequired) {
    for (const std::string choice : {"auto", "required"}) {
        OpenAIRequest request;
        request.toolChoice = choice;
        request.toolNameSchemaMap.emplace("question", ToolSchemaWrapper{nullptr, openCodeQuestionSchema});
        GenerationConfigBuilder builder({}, "gemma4", true, STANDARD);
        builder.parseConfigFromRequest(request);

        if (choice == "auto") {
            EXPECT_FALSE(builder.getConfig().structured_output_config);
        } else {
            const auto& tags = grammar<Structured::TagsWithSeparator>(builder.getConfig());
            ASSERT_EQ(tags.tags.size(), 1u);
            EXPECT_EQ(tags.tags[0].begin, "<|tool_call>call:question");
            EXPECT_EQ(std::get<Structured::JSONSchema>(tags.tags[0].content).value, openCodeQuestionSchema);
        }
    }
}

TEST(Gemma4GenerationContractTest, ImpossibleHardChoiceIsRejected) {
    for (bool guided : {false, true}) {
        for (const std::string choice : {"required", "missing"}) {
            OpenAIRequest request;
            request.toolChoice = choice;
            GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
            EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument);
        }
        auto request = requestWithTools("missing");
        GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
        EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument);
    }
}

TEST(Gemma4GenerationContractTest, ResponseFormatAndActiveToolsCannotSilentlyReplaceConstraints) {
    for (bool guided : {false, true}) {
        for (const std::string choice : {"auto", "required", "second"}) {
            auto request = requestWithTools(choice);
            request.responseFormat = responseSchema;
            GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
            EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument);
        }
    }
}

TEST(Gemma4GenerationContractTest, ObjectSchemaIsPassedWithoutLosingNestedConstraints) {
    const std::string schema = R"({"type":"object","properties":{"nested":{"type":"object","properties":{"x":{"enum":[1,2]}}},"array":{"type":"array","items":{"type":["number","boolean","null"]}},"optional":{"type":"string"}},"required":["nested"],"additionalProperties":false})";
    auto request = requestWithTools("first");
    request.toolNameSchemaMap.erase("second");
    request.toolNameSchemaMap["first"].stringRepr = schema;
    GenerationConfigBuilder builder({}, "gemma4", false, STANDARD);
    builder.parseConfigFromRequest(request);
    const auto& tags = grammar<Structured::TagsWithSeparator>(builder.getConfig());
    ASSERT_EQ(tags.tags.size(), 1u);
    EXPECT_EQ(std::get<Structured::JSONSchema>(tags.tags[0].content).value, schema);
}

TEST(Gemma4GenerationContractTest, RejectsHardNamesThatItsParserCannotExecute) {
    for (const std::string name : {"bad name", "", "bad:name"}) {
        OpenAIRequest request;
        request.toolChoice = "required";
        request.toolNameSchemaMap.emplace(name, ToolSchemaWrapper{nullptr, emptySchema});
        GenerationConfigBuilder builder({}, "gemma4", false, STANDARD);
        EXPECT_THROW(builder.parseConfigFromRequest(request), std::invalid_argument) << name;
    }
}

// Root-cause campaign contracts. These characterize current production behavior
// at 908bc8b7 and must not be "fixed" in this test session.

TEST(Gemma4GenerationContractTest, NamedToolChoiceInstallsStructuralOutput) {
    auto request = requestWithTools("second");
    GenerationConfigBuilder builder({}, "gemma4", true, STANDARD);
    builder.parseConfigFromRequest(request);
    ASSERT_TRUE(builder.getConfig().structured_output_config.has_value());
    const auto& tags = grammar<Structured::TagsWithSeparator>(builder.getConfig());
    ASSERT_EQ(tags.tags.size(), 1u);
    EXPECT_EQ(tags.tags[0].begin, "<|tool_call>call:second");
    EXPECT_EQ(tags.tags[0].end, "<tool_call|>");
    EXPECT_TRUE(tags.at_least_one);
}

TEST(Gemma4GenerationContractTest, RequiredToolChoiceInstallsStructuralOutputWithAtLeastOne) {
    auto request = requestWithTools("required");
    GenerationConfigBuilder builder({}, "gemma4", true, STANDARD);
    builder.parseConfigFromRequest(request);
    ASSERT_TRUE(builder.getConfig().structured_output_config.has_value());
    const auto& tags = grammar<Structured::TagsWithSeparator>(builder.getConfig());
    EXPECT_TRUE(tags.at_least_one);
    EXPECT_FALSE(tags.stop_after_first);
    ASSERT_EQ(tags.tags.size(), 2u);
}

TEST(Gemma4GenerationContractTest, AutoPlusEnableToolGuidedGenerationResetsStructuredOutput) {
    // Current production contract: Gemma4 auto ignores enable_tool_guided_generation
    // and clears structured_output_config. Do not treat this as a regression to patch.
    for (bool guided : {false, true}) {
        auto request = requestWithTools("auto");
        GenerationConfigBuilder builder({}, "gemma4", guided, STANDARD);
        builder.parseConfigFromRequest(request);
        EXPECT_FALSE(builder.getConfig().structured_output_config.has_value())
            << "guided=" << guided
            << " Gemma4 auto must leave structured_output_config empty/reset";
        EXPECT_FALSE(builder.hasHardToolChoice());
    }
}

TEST(Gemma4GenerationContractTest, SamplingInheritsBaseTemperatureAndRandomizesOmittedSeed) {
    ov::genai::GenerationConfig base;
    base.temperature = 1.0f;
    base.rng_seed = 0;
    base.num_beams = 1;

    {
        OpenAIRequest omitted;
        GenerationConfigBuilder builder(base, "gemma4", false, STANDARD);
        builder.parseConfigFromRequest(omitted);
        EXPECT_FLOAT_EQ(builder.getConfig().temperature, 1.0f);
        EXPECT_TRUE(builder.getConfig().do_sample);
        EXPECT_NE(builder.getConfig().rng_seed, 0u);
    }
    {
        OpenAIRequest greedy;
        greedy.temperature = 0.0f;
        GenerationConfigBuilder builder(base, "gemma4", false, STANDARD);
        builder.parseConfigFromRequest(greedy);
        EXPECT_FLOAT_EQ(builder.getConfig().temperature, 0.0f);
        EXPECT_FALSE(builder.getConfig().do_sample);
        EXPECT_EQ(builder.getConfig().rng_seed, 0u);
    }
    {
        OpenAIRequest fixed;
        fixed.temperature = 0.9f;
        fixed.seed = 42;
        GenerationConfigBuilder builder(base, "gemma4", false, STANDARD);
        builder.parseConfigFromRequest(fixed);
        EXPECT_FLOAT_EQ(builder.getConfig().temperature, 0.9f);
        EXPECT_TRUE(builder.getConfig().do_sample);
        EXPECT_EQ(builder.getConfig().rng_seed, 42u);
    }
}

TEST(Gemma4VsHermesGuidedGenerationReference, AutoHonorsTriggeredTagsOnlyForHermesQwen) {
    using Triggered = ov::genai::StructuredOutputConfig::TriggeredTags;
    auto request = requestWithTools("auto");

    GenerationConfigBuilder gemma({}, "gemma4", true, STANDARD);
    gemma.parseConfigFromRequest(request);
    EXPECT_FALSE(gemma.getConfig().structured_output_config.has_value())
        << "Gemma4 auto + enable_tool_guided_generation currently does not install trigger-scoped tags";

    GenerationConfigBuilder hermes({}, "hermes3", true, STANDARD);
    hermes.parseConfigFromRequest(request);
    ASSERT_TRUE(hermes.getConfig().structured_output_config.has_value());
    const auto& triggered = grammar<Triggered>(hermes.getConfig());
    ASSERT_FALSE(triggered.triggers.empty());
    EXPECT_EQ(triggered.triggers.front(), "<tool_call>");
    EXPECT_FALSE(triggered.at_least_one);
    EXPECT_EQ(triggered.tags.size(), 2u);

    GenerationConfigBuilder qwen({}, "qwen3", true, STANDARD);
    qwen.parseConfigFromRequest(request);
    ASSERT_TRUE(qwen.getConfig().structured_output_config.has_value());
    const auto& qwenTriggered = grammar<Triggered>(qwen.getConfig());
    EXPECT_FALSE(qwenTriggered.at_least_one);
    ASSERT_FALSE(qwenTriggered.triggers.empty());
    EXPECT_EQ(qwenTriggered.triggers.front(), "<tool_call>");
}
