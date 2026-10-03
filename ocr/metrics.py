"""Exact sequence accuracy and corpus character error rate."""
import torch
from .ctc import ctc_loss, decode_prediction


def edit_distance(reference, prediction):
    previous = list(range(len(prediction) + 1))
    for i, char in enumerate(reference, start=1):
        current = [i]
        for j, other in enumerate(prediction, start=1):
            current.append(min(current[-1] + 1, previous[j] + 1,
                               previous[j - 1] + (char != other)))
        previous = current
    return previous[-1]


@torch.inference_mode()
def evaluate_loader(model, loader, device):
    model.eval()
    count = correct = errors = characters = 0
    loss_sum = 0.0
    for images, targets, lengths, labels in loader:
        logits = model(images.to(device))
        loss = ctc_loss(logits, targets.to(device), lengths)
        if not torch.isfinite(loss):
            raise RuntimeError('Nonfinite validation CTC loss')
        predictions = [decode_prediction(path) for path in logits.argmax(2).transpose(0, 1).cpu()]
        count += len(labels)
        loss_sum += loss.item() * len(labels)
        correct += sum(pred == label for pred, label in zip(predictions, labels))
        errors += sum(edit_distance(label, pred) for pred, label in zip(predictions, labels))
        characters += sum(map(len, labels))
    if count == 0:
        raise ValueError('Evaluation dataset is empty')
    return {'loss': loss_sum / count, 'exact_sequence_accuracy': correct / count,
            'character_error_rate': errors / characters, 'samples': count}
