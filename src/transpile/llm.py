import logging
import os

from dotenv import load_dotenv
from openai import OpenAI

from ..paths import REPO_ROOT

load_dotenv()

logger = logging.getLogger(__name__)


def log_write(tag: str, message: str) -> None:
    """Lightweight query logger; visible under `--verbose` via the root logging config."""
    logger.debug("[%s] %s", tag, message)

provider_info = {
    "OpenAI": {
        "name": "OpenAI",
        "default_model": "o4-mini",
        "default_leanaide_model": "gpt-5.4",
        "api_key": os.getenv("OPENAI_API_KEY", "Key Not Found"),
        "models_url":"https://platform.openai.com/docs/models"
    },
    "Gemini": {
        "name": "Gemini",
        "default_model": "gemini-2.5-pro",
        "default_leanaide_model": "gemini-1.5-pro",
        "api_key": os.getenv("GEMINI_API_KEY", "Key Not Found"),
        "models_url": "https://developers.generativeai.google/models"
    },
    "OpenRouter": {
        "name": "OpenRouter",
        "default_model": "openai/gpt-5.4",
        "default_leanaide_model": "openai/gpt-5.4",
        "api_key": os.getenv("OPENROUTER_API_KEY", "Key Not Found"),
        "models_url": "https://openrouter.ai/models"
    },
    "DeepInfra": {
        "name": "DeepInfra",
        "default_model": "deepseek-ai/DeepSeek-R1-0528",
        "default_leanaide_model": "deepseek-ai/DeepSeek-R1-0528",
        "api_key": os.getenv("DEEPINFRA_API_KEY", "Key Not Found"),
        "models_url": "https://deepinfra.com/models"
    }
}

# Extract API keys for backwards compatibility
OPENAI_API_KEY = provider_info["OpenAI"]["api_key"]
GEMINI_API_KEY = provider_info["Gemini"]["api_key"]
OPENROUTER_API_KEY = provider_info["OpenRouter"]["api_key"]
DEEPINFRA_API_KEY = provider_info["DeepInfra"]["api_key"]

# Every provider here speaks the OpenAI chat/models API, so one client type covers all four.
PROVIDER_BASE_URLS = {
    "openai": None,
    "gemini": "https://generativelanguage.googleapis.com/v1beta/openai/",
    "openrouter": "https://openrouter.ai/api/v1",
    "deepinfra": "https://api.deepinfra.com/v1/openai",
}

# The pre-pass prompts are checked-in documents, read from docs/ at the repo root.
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
CONTRACT_PROMPT_SYSTEM= os.path.join(DOCS_DIR, "contract-prompt-system.md")
VERIFIABLE_DESIGN_PROMPT = os.path.join(DOCS_DIR, "verifiable-python-design.md")


class LLMError(RuntimeError):
    """No usable API key, or the provider refused the request."""


def env_api_key(provider: str) -> str | None:
    """The provider's key from the environment (`.env` / `OPENAI_API_KEY` / …), or None."""
    for name, info in provider_info.items():
        if name.lower() == provider.lower():
            key = info["api_key"]
            return None if key == "Key Not Found" else key
    return None


def match_provider_client(provider: str = "gemini", api_key: str | None = None):
    """A client for `provider`. `api_key` overrides the environment.

    Clients are built per call rather than at import: `pastalean serve` receives a key per request,
    and a module-level client would freeze whatever was in the environment when Python started.
    Constructing one opens no connection, so this is cheap.
    """
    provider = provider.lower()
    if provider not in PROVIDER_BASE_URLS:
        provider = "openai"  # Default to OpenAI if provider is not recognized
    key = api_key or env_api_key(provider)
    if not key:
        raise LLMError(f"no API key for {provider}: pass one, or set {provider.upper()}_API_KEY")
    base_url = PROVIDER_BASE_URLS[provider]
    return OpenAI(api_key=key, base_url=base_url) if base_url else OpenAI(api_key=key)


def default_model_for(provider: str) -> str:
    """The default chat model for a provider name (case-insensitive), matching `provider_info`.
    Lets callers pass only a provider and get the right model without hard-coding one."""
    for key, info in provider_info.items():
        if key.lower() == provider.lower():
            return info["default_model"]
    return "gemini-2.5-pro"


## Get model list supported by API KEY
def get_supported_models(provider, api_key: str | None = None):
    """
    The model ids the given API key can reach, sorted. Raises `LLMError` if the provider rejects it.
    """
    client = match_provider_client(provider, api_key)
    try:
        return sorted(model.id for model in client.models.list().data)
    except LLMError:
        raise
    except Exception as err:  # noqa: BLE001  (any transport/auth failure is the caller's problem)
        raise LLMError(f"could not list {provider} models: {err}") from err


def model_response_gen(prompt:str, task:str = "", provider = "gemini", model:str ="gemini-2.5-pro",
                       json_output: bool = False, api_key: str | None = None):
    """
    GPT response generator function.
    Args:
        prompt (str): The prompt to send to the GPT model.
        task (str): Optional system message to set the context for the model.
        model (str): The model to use for generating the response.
        provider (str): The provider to use for the model (e.g., "openai", "gemini", "openrouter", "deepinfra").
        json_output (bool): Request a JSON object response (`response_format={"type": "json_object"}`).
        api_key (str): Overrides the provider's environment key.
    """
    messages = []
    if task != "":
        messages.append({
            "role": "system",
            "content": task
        })
    messages.append({
        "role": "user",
        "content": prompt,
    })

    client = match_provider_client(provider, api_key)
    # Never log `api_key`.
    log_write("llm_query", f"provider={provider} model={model} json={json_output} prompt={prompt[:60]!r}...")
    create_kwargs = {"model": model, "messages": messages}
    if json_output:
        create_kwargs["response_format"] = {"type": "json_object"}
    response = client.chat.completions.create(**create_kwargs)
    if response is None:
        return "No response from model."

    return response.choices[0].message.content

def extract_python(code: str):
    """
    Extract Python code from a string that may contain code blocks.
    Args:
        code (str): The input string containing code blocks.
    """
    if code.startswith("```python"):
        code = code[len("```python"):]
    if code.startswith("```"):
        code = code[len("```"):]
    if code.endswith("```"):
        code = code[:-len("```")]
    return code.strip()

def contract_code(code: str, provider = "gemini", model=None, goal=None, api_key: str | None = None):
    """
    Insert formal-method contracts (Requires/Ensures/Invariant/Assert/…) into a Python snippet.
    Args:
        code (str): The input Python code snippet.
        provider (str): The provider to use for the model (e.g., "openai", "gemini", "openrouter", "deepinfra").
        model (str): The model to use; defaults to the provider's default chat model.
        goal (str): Optional natural-language statement of what the user wants to be able to prove.
            When given, it is passed to the model so the inserted contracts/asserts are tailored to it.
    """
    model = model or default_model_for(provider)
    with open(CONTRACT_PROMPT_SYSTEM, 'r') as f:
        system_prompt = f.read()

    # The system prompt carries all the instructions and worked examples; the user turn is just the
    # program to annotate, fenced so the model returns the same shape.
    user_prompt = f"```python\n{code}\n```"
    if goal:
        user_prompt += (
            "\n\nThe user wants to be able to PROVE the following about this code. Tailor the contracts "
            "— especially the Ensures (the postcondition) and any bridging Asserts and loop invariants — "
            f"so that this goal becomes provable, and treat it as the function's intent:\n{goal}"
        )

    response = model_response_gen(user_prompt, task=system_prompt, provider=provider, model=model,
                                  api_key=api_key)
    if response is None:
        return "No response from model."
    return extract_python(response)

def verifiable_design_code(code: str, provider = "gemini", model=None, api_key: str | None = None):
    """
    Restructure a Python snippet to maximise its provable surface, guided by the verifiable-design doc.
    Args:
        code (str): The input Python code snippet.
        provider (str): The provider to use for the model (e.g., "openai", "gemini", "openrouter", "deepinfra").
        model (str): The model to use; defaults to the provider's default chat model.
    """
    model = model or default_model_for(provider)
    with open(VERIFIABLE_DESIGN_PROMPT, 'r') as f:
        system_prompt = f.read()

    user_prompt = (
        "Rewrite the following Python program to maximise its provable surface per the design guide: "
        "keep each piece of math as a pure single-expression function, and push every print, input, "
        "raise, and try/except to the edge (a `main` entry point) so the math functions never read "
        "input, print, or raise. Preserve the program's observable behaviour. Output ONLY the rewritten "
        f"program in a single ```python code block.\n\n```python\n{code}\n```"
    )

    response = model_response_gen(user_prompt, task=system_prompt, provider=provider, model=model,
                                  api_key=api_key)
    if response is None:
        return "No response from model."
    return extract_python(response)