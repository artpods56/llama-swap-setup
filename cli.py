import json
import os
import shutil
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional

import requests
from tqdm import tqdm
import rich_click as click
from dotenv import load_dotenv
from jinja2 import Environment, FileSystemLoader
from pydantic import BaseModel, Field, ValidationError
from structlog import get_logger

load_dotenv()

logger = get_logger(__name__)

class ModelType(Enum):
    GGUF = "gguf"
    SAFETENSORS = "safetensors"

class BaseModelConfig(BaseModel):
    name: str = Field(..., description="The identification of the model.")
    description: str = Field(description="The description of the model.")
    runtime_kwargs: Dict[str, str] = Field(default_factory=dict, description="Runtime kwargs for the model.")



class GGUFModelsConfig(BaseModelConfig):
    model_type: ModelType = ModelType.GGUF
    url: str = Field(..., description="The url of the model.")
    mmproj: Optional[str] = Field(
        default=None,
        description="Optional multimodal projector URL. Filename is rendered as mmproj_{name}.gguf.",
    )



class SafetensorsModelsConfig(BaseModelConfig):
    model_type: ModelType = ModelType.SAFETENSORS
    pass


class ModelsConfig(BaseModel):
    ggufs: List[GGUFModelsConfig] = Field(description="The list of GGUF models.")
    safetensors: List[SafetensorsModelsConfig] = Field(description="The list of Safetensors models.")


def _load_and_validate_models(models_file_path: str) -> Dict:
    with open(models_file_path, "r") as file_handle:
        model_definitions: Dict = json.loads(file_handle.read())

    try:
        validated_definitions = ModelsConfig(**model_definitions)
        logger.info("Models validated.", validated_definition=validated_definitions)
    except ValidationError as error:
        logger.error("Config failed serialization.", error=error)
        raise

    return model_definitions


def _render_template(template_path: str, models_definition: Dict) -> str:
    template_directory = str(Path(template_path).parent)
    template_name = Path(template_path).name

    environment = Environment(loader=FileSystemLoader(template_directory))
    template = environment.get_template(template_name)

    flattened_model_definitions: Dict[str, Dict] = {}
    for model_type_key in models_definition:
        for model in models_definition[model_type_key]:
            model["model_type"] = model_type_key
            flattened_model_definitions[model["name"]] = model

    return template.render(models=flattened_model_definitions)


@click.group()
def cli() -> None:
    """Llama Swap Setup CLI"""
    pass


@cli.command(name="inject-models")
@click.option("--models-file", default="models.json", help="Path to models.json")
@click.option(
    "--template",
    default="configs/templates/config.base.yaml",
    help="Path to Jinja template file",
)
@click.option(
    "--output",
    default="configs/config.base.yaml",
    help="Path to write rendered base config",
)
@click.option("--overwrite", is_flag=True, help="Overwrite output file if exists")
def inject_models(models_file: str, template: str, output: str, overwrite: bool) -> None:
    models_file_path = os.path.join(os.getcwd(), models_file)
    output_path = os.path.join(os.getcwd(), output)
    template_path = os.path.join(os.getcwd(), template)

    models_definition = _load_and_validate_models(models_file_path)
    rendered_config = _render_template(template_path, models_definition)

    if Path(output_path).exists():
        if overwrite:
            os.remove(output_path)
        else:
            raise FileExistsError(f"Output file already exists: {output_path}")

    with open(output_path, "w") as output_handle:
        output_handle.write(rendered_config)

def get_models_directory():
    models_dir = os.getenv("MODELS_DIR", "models")
    return Path(os.getcwd()) / Path(models_dir)

def _download_file(url, destination):
    if destination.exists():
        logger.info("File already exists, skipping download.", destination=destination)
        return

    try:
        # Support local file URLs without progress bar
        if str(url).startswith("file://"):
            local_path = str(url).replace("file://", "")
            total_size = os.path.getsize(local_path) if os.path.exists(local_path) else None
            with open(local_path, 'rb') as src, open(destination, 'wb') as dst:
                if total_size and total_size > 0:
                    with tqdm(total=total_size, unit='B', unit_scale=True, desc=f"{Path(destination).name}") as pbar:
                        for chunk in iter(lambda: src.read(1024 * 1024), b""):
                            dst.write(chunk)
                            pbar.update(len(chunk))
                else:
                    shutil.copyfileobj(src, dst)
            return

        # Remote downloads with streaming and progress bar
        with requests.get(url, stream=True) as response:
            response.raise_for_status()
            total_size = int(response.headers.get('content-length', 0))
            chunk_size = 1024 * 1024
            with open(destination, 'wb') as out_file:
                if total_size > 0:
                    with tqdm(total=total_size, unit='B', unit_scale=True, desc=f"{Path(destination).name}") as pbar:
                        for chunk in response.iter_content(chunk_size=chunk_size):
                            if chunk:
                                out_file.write(chunk)
                                pbar.update(len(chunk))
                else:
                    # Fallback if server didn't send content-length
                    for chunk in response.iter_content(chunk_size=chunk_size):
                        if chunk:
                            out_file.write(chunk)
    except requests.exceptions.RequestException as e:
        print("Error downloading the file:", e)

def download_model_files(model: GGUFModelsConfig | SafetensorsModelsConfig):

    models_directory = get_models_directory()

    if isinstance(model, GGUFModelsConfig):
        model_directory = models_directory / Path(model.model_type.value) / Path(model.name)

        model_directory.mkdir(parents=True, exist_ok=True)

        _download_file(model.url, model_directory / Path(f"{model.name}.gguf"))
        if model.mmproj:
            _download_file(model.mmproj, model_directory / Path(f"mmproj_{model.name}.gguf"))
    elif isinstance(model, SafetensorsModelsConfig):
        model_directory = models_directory / Path(model.model_type.value)
        model_directory.mkdir(parents=True, exist_ok=True)
        raise NotImplementedError("Downloading safetensors models at runtime is not yet supported.")
    else:
        raise ValueError(f"Invalid model type: {model.model_type}")


@cli.command(name="download-models")
@click.option("--models-file", default="models.json", help="Path to models.json")
@click.option("--models-dir", default="models", help="Directory to store downloaded models")
@click.option("--overwrite", is_flag=True, help="Overwrite existing files if present")
def download_models(models_file: str, models_dir: str, overwrite: bool) -> None:
    models_file_path = os.path.join(os.getcwd(), models_file)
    models_definition = _load_and_validate_models(models_file_path)
    for model in models_definition.get("ggufs", []):
        parsed_model = GGUFModelsConfig(**model)
        download_model_files(parsed_model)



if __name__ == "__main__":
    cli()
