"""Offline supervised training. Run: python -m ocr.train --help."""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import torch
from torch.utils.data import DataLoader
from .config import DEFAULT_CHECKPOINT, ModelConfig, PreprocessingConfig, TrainingConfig
from .ctc import ctc_loss
from .dataset import CellDataset, collate_cells, ensure_disjoint, split_dataset
from .metrics import evaluate_loader
from .model import MarksCRNN
from .runtime import seed_everything, select_device, save_checkpoint


def train(train_manifest, val_manifest=None, *, output=DEFAULT_CHECKPOINT,
          config=TrainingConfig(), preprocessing=PreprocessingConfig(), model_config=ModelConfig()):
    seed_everything(config.seed)
    device = select_device(config.device)
    dataset = CellDataset(train_manifest, preprocessing=preprocessing)
    if val_manifest is None:
        training, validation = split_dataset(dataset, config.validation_fraction, config.seed)
    else:
        training = dataset
        validation = CellDataset(val_manifest, preprocessing=preprocessing)
    ensure_disjoint(training, validation)
    options = {'batch_size': config.batch_size, 'collate_fn': collate_cells,
               'num_workers': config.num_workers, 'pin_memory': device.type == 'cuda'}
    generator = torch.Generator().manual_seed(config.seed)
    training_loader = DataLoader(training, shuffle=True, generator=generator, **options)
    validation_loader = DataLoader(validation, shuffle=False, **options)
    model = MarksCRNN(model_config).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=config.learning_rate, weight_decay=config.weight_decay)
    output = Path(output)
    checkpoint_directory = output.parent / f'{output.stem}_checkpoints'
    checkpoint_directory.mkdir(parents=True, exist_ok=True)
    # Persist actual split membership for later leakage audits.
    split_record = {name: [{'image_path': str(s.image_path), 'label': s.label, 'group': s.group}
                          for s in data.samples]
                    for name, data in [('train', training), ('val', validation)]}
    (checkpoint_directory / 'split.json').write_text(json.dumps(split_record, indent=2), encoding='utf-8')
    best_key = (-1.0, -float('inf'))
    history = []
    for epoch in range(1, config.epochs + 1):
        model.train()
        loss_sum = 0.0
        for images, targets, lengths, _ in training_loader:
            logits = model(images.to(device))
            loss = ctc_loss(logits, targets.to(device), lengths)
            if not torch.isfinite(loss):
                raise RuntimeError('Nonfinite training CTC loss')
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            loss_sum += loss.item() * images.size(0)
        metrics = evaluate_loader(model, validation_loader, device)
        record = {'epoch': epoch, 'device': str(device), 'training_loss': loss_sum / len(training),
                  'validation_loss': metrics['loss'],
                  'exact_sequence_accuracy': metrics['exact_sequence_accuracy'],
                  'character_error_rate': metrics['character_error_rate']}
        history.append(record)
        print(json.dumps(record), flush=True)
        metadata = {'epoch': epoch, 'metrics': record, 'training_config': asdict(config),
                    'optimizer_state': optimizer.state_dict()}
        save_checkpoint(checkpoint_directory / f'epoch_{epoch:03d}.pth', model, preprocessing, **metadata)
        key = (metrics['exact_sequence_accuracy'], -metrics['loss'])
        if key > best_key:
            best_key = key
            save_checkpoint(output, model, preprocessing, **metadata)
        (checkpoint_directory / 'history.json').write_text(json.dumps(history, indent=2), encoding='utf-8')
    return history


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--train', required=True, help='CSV: image_path,label[,group]')
    parser.add_argument('--val', help='Separate validation CSV; otherwise split --train')
    parser.add_argument('--output', default=str(DEFAULT_CHECKPOINT))
    parser.add_argument('--epochs', type=int, default=30)
    parser.add_argument('--batch-size', type=int, default=32)
    parser.add_argument('--learning-rate', type=float, default=0.001)
    parser.add_argument('--weight-decay', type=float, default=0.0001)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--validation-fraction', type=float, default=0.2)
    parser.add_argument('--device', choices=['auto', 'cpu', 'cuda'], default='auto')
    parser.add_argument('--workers', type=int, default=0)
    parser.add_argument('--preprocessing-config', help='JSON with PreprocessingConfig fields')
    args = parser.parse_args()
    preprocessing = (PreprocessingConfig(**json.loads(Path(args.preprocessing_config).read_text()))
                     if args.preprocessing_config else PreprocessingConfig())
    train(args.train, args.val, output=args.output, preprocessing=preprocessing,
          config=TrainingConfig(epochs=args.epochs, batch_size=args.batch_size,
                                learning_rate=args.learning_rate, weight_decay=args.weight_decay,
                                seed=args.seed, validation_fraction=args.validation_fraction,
                                device=args.device, num_workers=args.workers))


if __name__ == '__main__':
    main()
