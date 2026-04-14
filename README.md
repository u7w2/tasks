# Tasks Graph

A task management application that visualizes tasks as a **Directed Acyclic Graph (DAG)**. Organise complex projects by mapping dependencies and viewing them across depth-based columns.

## Basic Usage

- **Create Tasks**: Use the `+` button in the app bar (iOS) or the Floating Action Button (Android) to add a new task.
- **Select & Move**: Tap a task to select it. You can then drag it to move it.
- **Manage Dependencies**: Drag a task **onto another task** to make it a dependent. Dragging it onto the same task again will remove the dependency link.
- **Reorder**: Drag a task **between** two other task nodes to reorder them within a column.
- **Rename**: Press and hold (Long Press) on any task card to edit its name inline.
- **Manage Workflows**: Access the side menu (Android) or top-left menu (iOS) to switch between different workflows, create new ones, or delete existing ones.
- **Save & Share**: Use the overflow menu (...) to **Export** or **Import** your workflows as JSON files.

## Installation

Pre-compiled binaries are available for both mobile platforms:

1. Go to the [Releases](https://github.com/u7w2/tasks/releases) section of this repository.
2. Download the appropriate file for your device:
   - **Android**: Download the `.apk` file and install it on your device.
   - **iOS**: You'll have to compile this yourself by cloning this repository and building the app using Flutter SDK.

## Platform Compatibility

- **Android**: Full support with Material Design.
- **iOS**: Adaptive Cupertino UI is implemented for a native look and feel. Please note that the iOS version is currently experimental, not fully mature.

---
For a list of planned features and known bugs, see [ROADMAP.md](./ROADMAP.md).
