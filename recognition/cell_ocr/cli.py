import argparse
import json
import random
from pathlib import Path
import torch
from PIL import Image
from torch.utils.data import DataLoader
from .data import CellDataset, collate
from .decoding import greedy_decode
from .inference import CellRecognizer, FORMAT_VERSION
from .model import CRNN


def train(args):
    if args.epochs < 1 or args.batch_size < 1:
        raise ValueError("Epochs and batch size must be positive")
    random.seed(args.seed)
    torch.manual_seed(args.seed)
    training, validation = CellDataset(args.train), CellDataset(args.validation)
    if {p for p, _ in training.samples} & {p for p, _ in validation.samples}:
        raise ValueError("Training and validation image paths overlap")
    train_loader = DataLoader(training, batch_size=args.batch_size, shuffle=True, collate_fn=collate)
    val_loader = DataLoader(validation, batch_size=args.batch_size, collate_fn=collate)
    model = CRNN()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    criterion = torch.nn.CTCLoss(blank=0)
    best = -1.0
    for epoch in range(args.epochs):
        model.train()
        loss_sum = 0.0
        for images, targets, lengths, _ in train_loader:
            logits = model(images).log_softmax(2)
            input_lengths = torch.full((images.size(0),), logits.size(0), dtype=torch.long)
            loss = criterion(logits, targets, input_lengths, lengths)
            if not torch.isfinite(loss):
                raise RuntimeError("Nonfinite CTC training loss")
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            loss_sum += loss.item() * images.size(0)
        model.eval()
        correct = 0
        with torch.inference_mode():
            for images, _, _, labels in val_loader:
                paths = model(images).argmax(2).transpose(0, 1).tolist()
                correct += sum(greedy_decode(path) == label for path, label in zip(paths, labels))
        accuracy = correct / len(validation)
        print(json.dumps({"epoch": epoch + 1, "train_loss": loss_sum / len(training), "validation_exact_accuracy": accuracy}))
        if accuracy > best:
            best = accuracy
            Path(args.output).parent.mkdir(parents=True, exist_ok=True)
            torch.save({"format_version": FORMAT_VERSION, "model_state": model.state_dict(),
                        "seed": args.seed, "validation_exact_accuracy": accuracy}, args.output)


def main():
    parser = argparse.ArgumentParser(description="Handwritten integer cell OCR")
    commands = parser.add_subparsers(dest="command", required=True)
    training = commands.add_parser("train")
    training.add_argument("--train", required=True)
    training.add_argument("--validation", required=True)
    training.add_argument("--output", required=True)
    training.add_argument("--epochs", type=int, default=30)
    training.add_argument("--batch-size", type=int, default=32)
    training.add_argument("--seed", type=int, default=42)
    prediction = commands.add_parser("predict")
    prediction.add_argument("--checkpoint", required=True)
    prediction.add_argument("--image", required=True)
    prediction.add_argument("--maximum", type=int, default=99)
    args = parser.parse_args()
    if args.command == "train":
        train(args)
    else:
        recognizer = CellRecognizer(args.checkpoint)
        with Image.open(args.image) as image:
            print(json.dumps(recognizer.recognize(image, args.maximum).to_dict()))


if __name__ == "__main__":
    main()
