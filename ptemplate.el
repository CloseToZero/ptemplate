;;; ptemplate.el --- Project templates -*- lexical-binding: t -*-

;; Copyright (C) 2020  Nikita Bloshchanevich

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;; Author: Nikita Bloshchanevich <nikblos@outlook.com>
;; URL: https://github.com/nbfalcon/ptemplate
;; Package-Requires: ((emacs "25.1") (yasnippet "0.13.0"))
;; Version: 0.1

;;; Commentary:
;; Creating projects can be a lot of work. Cask files need to be set up, a
;; License file must be added, maybe build system files need to be created. A
;; lot of that can be automated, which is what ptemplate does. You can create a
;; set of templates categorized by type/template like in eclipse, and ptemplate
;; will then initialize the project for you. In the template you can have any
;; number of yasnippets or normal files.

;; Security note: yasnippets allow arbitrary code execution, as do .ptemplate.el
;; files. DO NOT EXPAND UNTRUSTED PTEMPLATES. Ptemplate DOES NOT make ANY
;; special effort to protect against malicious templates.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;;; (ptemplate-template-dirs :: [String])
(defcustom ptemplate-template-dirs '()
  "List of directories containing templates.
Analagous to the variable `yas-snippet-dirs'."
  :group 'ptemplate
  :type '(repeat string))

;;; (ptemplate-find-template :: String -> [String])
(defun ptemplate-find-templates (template)
  "Find TEMPLATE in `ptemplate-template-dirs'.
Template shall be a path of the form \"category/type\". Returns a
list of full paths to the template directory specified by
TEMPLATE. Returns the empty list if TEMPLATE cannot be found."
  (let ((template (file-name-as-directory template))
        (result))
    (dolist (dir ptemplate-template-dirs)
      (let ((template-dir (concat (file-name-as-directory dir) template)))
        (when (file-directory-p template-dir)
          (push template-dir result))))
    (nreverse result)))

(defun ptemplate-find-template (template)
  "Find TEMPLATE in `ptemplate-template-dirs'.
Unlike `ptemplate-find-templates', this function does not return
all occurrences, but only the first."
  (catch 'result
    (dolist (dir ptemplate-template-dirs)
      (let ((template-dir (concat (file-name-as-directory dir) template)))
        (when (file-directory-p template-dir)
          (throw 'result template-dir))))))

(defun ptemplate--list-dir (dir)
  "List DIR, including directories.
A list of the full paths of each element is returned. The special
directories \".\" and \"..\" are ignored."
  (cl-delete-if (lambda (f) (or (string= (file-name-base f) ".")
                                (string= (file-name-base f) "..")))
                (directory-files dir t)))

(defun ptemplate-list-template-dir (dir)
  "List all templates in directory DIR.
The result is of the form (TYPE ((NAME . PATH)...))...."
  (let* ((type-dirs (ptemplate--list-dir dir))
         (types (mapcar #'file-name-base type-dirs))
         (name-dirs (cl-loop for tdir in type-dirs collect
                             (ptemplate--list-dir tdir)))
         (name-dir-pairs (cl-loop for name-dir in name-dirs collect
                                  (cl-loop for dir in name-dir collect
                                           (cons (file-name-base dir) dir)))))
    (cl-mapcar #'cons types name-dir-pairs)))

(defun ptemplate-list-templates ()
  "List all templates in `ptemplate-template-dirs'.
The result is an alist ((TYPE (NAME . PATH)...)...)."
  (mapcan #'ptemplate-list-template-dir ptemplate-template-dirs))

(defun ptemplate--list-templates-helm ()
  "Make a list of helm sources from the user's templates.
Gather a list of the user's templates using
`ptemplate-list-templates' and convert each TYPE . TEMPLATES pair
into a helm source with TYPE as its header. Each helm source's
action is to create a new project in a directory prompted from
the user (see `ptemplate-exec-template').

Helm (in particular, helm-source.el) must already be loaded when
this function is called."
  (declare-function helm-make-source "helm" (name class &rest args))
  (cl-loop for entry in (ptemplate-list-templates) collect
           (helm-make-source (car entry) 'helm-source-sync
             :candidates (cdr entry))))

(defun ptemplate-prompt-template-helm ()
  "Prompt for a template using `helm'.
The prompt is a `helm' prompt where all templates are categorized
under their types (as `helm' sources). The return value is the
path to the template, as a string."
  (declare-function helm "helm")
  (require 'helm)
  (helm :sources (ptemplate--list-templates-helm) :buffer "*helm ptemplate*"))

(defface ptemplate-type-face '((t :inherit font-lock-function-name-face))
  "Face used to show template types in for the :completing-read backend.
When :completing-read is used as backend in
`ptemplate-template-prompt-function', all entries have a (TYPE)
STRING appended to it. That TYPE is propertized with this face."
  :group 'ptemplate-faces)

(defun ptemplate--list-templates-completing-read ()
  "Make a `completing-read' collection."
  (cl-loop for heading in (ptemplate-list-templates) nconc
           (let ((category (propertize (format "(%s)" (car heading))
                                       'face 'ptemplate-type-face)))
             (cl-loop for template in (cdr heading) collect
                      (cons (concat (car template) " " category)
                            (cdr template))))))

(defvar ptemplate--completing-read-history nil
  "History variable for `completing-read'-based template prompts.
If :completing-read is set as `ptemplate-template-prompt-function',
pass this variable as history argument to `completing-read'.")

(defun ptemplate-prompt-template-completing-read ()
  "Prompt for a template using `completing-read'.
The prompt is a list of \"NAME (TYPE)\". The return value is the
path to the template, as a string."
  (let ((ptemplates (ptemplate--list-templates-completing-read)))
    (alist-get (completing-read "Select template: " ptemplates
                                nil t nil 'ptemplate--completing-read-history)
               ptemplates nil nil #'string=)))

(defcustom ptemplate-template-prompt-function
  #'ptemplate-prompt-template-completing-read
  "Prompting method to use to read a template from the user.
The function shall take no arguments and return the path to the
template as a string."
  :group 'ptemplate
  :type '(radio
          (const :tag "completing-read (ivy, helm, ...)"
                 #'ptemplate-prompt-template-completing-read)
          (const :tag "helm" #'ptemplate-prompt-template-helm)
          (function :tag "Custom function")))

(defcustom ptemplate-workspace-alist '()
  "Alist mapping between template types and workspace folders."
  :group 'ptemplate
  :type '(alist :key-type (string :tag "Type")
                :value-type (string :tag "Workspace")))

(defcustom ptemplate-default-workspace nil
  "Default workspace for `ptemplate-workspace-alist'.
If looking up a template's type in `ptemplate-workspace-alist'
fails, because there is no corresponding entry, use this as a
workspace instead."
  :group 'ptemplate
  :type 'string)

(defun ptemplate--prompt-target (template)
  "Prompt the user to supply a project directory for TEMPLATE.
The initial directory is looked up based on
`ptemplate-workspace-alist'. TEMPLATE's type is deduced from its
path, which means that it should have been obtained using
`ptemplate-list-templates', or at least be in a template
directory."
  (let* ((base (directory-file-name template))
         (type (file-name-nondirectory (directory-file-name
                                        (file-name-directory base))))
         (workspace (alist-get type ptemplate-workspace-alist
                               ptemplate-default-workspace nil #'string=)))
    (read-file-name "Create project: " workspace workspace)))

;;; (ptemplate--snippet-chain :: (Cons String String) | Buffer)
(defvar-local ptemplate--snippet-chain nil
  "Cons pointer to list of (SNIPPET . TARGET) or BUFFER.
Template directories can have any number of yasnippet files.
These need to be filled in by the user. To do this, there is a
snippet chain: a list of snippets and their target files or
buffers. During expansion of a template directory, first all
snippets are gathered into a list, the first snippet of which is
then shown to the user. If the user presses
\\<ptemplate-snippet-chain-mode-map>
\\[ptemplate-snippet-chain-next], the next item in the snippet
chain is displayed. Buffers are appended to this list when the
user presses \\<ptemplate-snippet-chain-mode-map>
\\[ptemplate-snippet-chain-later].

To facilitate the expansion of multiple templates at once, the
snippet chain must be buffer-local. However, if each buffer has
its own list, updates to it wouldn't be synced across buffers
stored for later finalization. Such buffers would contain already
finalized filenames in their snippet chain. Because of this, a
solution needs to be devised to share a buffer local value
between multiple buffers, and `ptemplate--snippet-chain' works as
follows: This variable actually stores a cons, the `cdr' of which
points to the actual snippet chain, as described above, the `car'
always being ignored. This way (pop (cdr
`ptemplate--snippet-chain')) modifies it in a way that is shared
between all buffers.

See also `ptemplate--snippet-chain-start'.")

(defvar-local ptemplate--snippet-chain-finalize-hook nil
  "Hook to run after the snippet chain finishes.
Each function therein gets called without arguments.

This hook is a snippet-env variable and not simply appended to
the list, as it would be executed *before* the end of snippet
expansion if `ptemplate-snippet-chain-later' is called during
expansion.")

(defvar-local ptemplate--snippet-chain-env nil
  "List of variables to set in snippet-chain buffers.
Alist of (SYMBOL . VALUE).
`ptemplate--snippet-chain-finalize-hook',
`ptemplate--snippet-chain-env', ... should not be included. All
variables will be made buffer-local before being set, so
`defvar-local' is not necessary.")

;;; (ptemplate--read-file :: String -> String)
(defun ptemplate--read-file (file)
  "Read FILE and return its contents a string."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(define-minor-mode ptemplate-snippet-chain-mode
  "Minor mode for template directory snippets.
This mode is only for keybindings."
  :init-value nil
  :lighter nil
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-c") #'ptemplate-snippet-chain-next)
            (define-key map (kbd "C-c C-l") #'ptemplate-snippet-chain-later)
            map))

(defun ptemplate--snippet-chain-continue ()
  "Make the next snippt/buffer in the snippet chain current."
  (require 'yasnippet)
  (declare-function yas-minor-mode "yasnippet" (&optional arg))
  (declare-function yas-expand-snippet "yasnippet" (s &optional start end env))
  ;; the snippet chain is a cons abused as a pointer: car is never used, while
  ;; cdr is modified; the cons can be shared between multiple buffers, sharing
  ;; the actual payload (which is always in the cdr). (See
  ;; `ptemplate--snippet-chain' for details).
  (let ((next (pop (cdr ptemplate--snippet-chain))))
    (cond
     ((null next) (run-hooks 'ptemplate--snippet-chain-finalize-hook))
     ((bufferp next) (switch-to-buffer next))
     ((consp next)
      (let ((oldbuf (current-buffer))
            (next-file (cdr next))
            (source-file (car next)))
        (find-file next-file)

        ;; Inherit snippet chain variables. NOTE: `ptemplate--snippet-chain',
        ;; ... are `defvar-local', so need not be made buffer-local.
        (dolist (sym '(ptemplate--snippet-chain
                       ptemplate--snippet-chain-env
                       ptemplate--snippet-chain-finalize-hook))
          (set sym (buffer-local-value sym oldbuf)))

        ;; set env
        (cl-loop for (sym . val) in ptemplate--snippet-chain-env do
                 (set (make-local-variable sym) val))

        (ptemplate-snippet-chain-mode 1)
        (yas-minor-mode 1)
        (yas-expand-snippet (ptemplate--read-file source-file)))))))

(defun ptemplate-snippet-chain-next ()
  "Save the current buffer and continue in the snippet chain.
The buffer is killed after calling this. If the snippet chain is
empty, do nothing."
  (interactive)
  (save-buffer 0)
  (let ((old-buf (current-buffer)))
    (ptemplate--snippet-chain-continue)
    (kill-buffer old-buf)))

(defun ptemplate-snippet-chain-later ()
  "Save the current buffer to be expanded later.
Use this if you are not sure yet what expansions to use in the
current snipept and want to decide later, after looking at
others."
  (interactive)
  (unless ptemplate--snippet-chain
    (user-error "No more snippets to expand"))
  ;; snippet chain cannot be nil, so nconc will append to it, modifying it
  ;; across all buffers.
  (nconc ptemplate--snippet-chain (list (current-buffer)))
  (ptemplate--snippet-chain-continue))

(defun ptemplate--snippet-chain-start (snippets &optional env finalize-hook)
  "Start a snippet chain with SNIPPETS.
For details, see `ptemplate--snippet-chain'.

ENV (alist of (SYMBOL . VALUE)) specifies the variables to set in
each new buffer.

FINALIZE-HOOK is called when the snippet chain finishes (see
`ptemplate--snippet-chain-finalize-hook')."
  (let ((ptemplate--snippet-chain (cons 'snippet-chain snippets))
        (ptemplate--snippet-chain-env env)
        (ptemplate--snippet-chain-finalize-hook finalize-hook))
    (ptemplate--snippet-chain-continue)))

;; HACKING NOTE: since ptemplate supports scripting within .ptemplate.el files,
;; certain variables need to be made available to that file for use with the
;; `ptemplate!' macro to hook into expansion. These variables should be defined
;; within this block, and made available by using `let' within
;; `ptemplate-expand-template'. `let' is used instead of `setq', as ptemplate
;; supports the expansion of multiple templates at once. This means that these
;; variables need to be overriden in separate contexts, potentially at once,
;; which was traditionally implemented using dynamic-binding. However, using
;; dynamic binding is recommended against; to still support the features of the
;; latter, Emacs allows `let' to override global variables in dynamic-binding
;; style, a feature made use of in `ptemplate-expand-template'.
(defvaralias 'ptemplate--after-copy-hook 'ptemplate--before-snippet-hook
  "Hook run after copying files.

Currently, this hook is always run before snippet expansion, and
is as such an alias for `ptemplate--before-snippet-hook', which
see.")

(defvar ptemplate--before-snippet-hook nil
  "Hook run before expanding yasnippets.
Each function therein shall take no arguments.

These variables are hooks to allow multiple ptemplate! blocks
that specify :before-yas, :after, ....")

(defvar ptemplate--finalize-hook nil
  "Hook to run after template expansion finishes.
At this point, no more files need to be copied and no more
snippets need be expanded.

See also `ptemplate--before-expand-hooks'.")

(defvar-local ptemplate--snippet-env nil
  "Environment used for snippet expansion.
Alist of (SYMBOL . VALUE). See also
`ptemplate--snippet-chain-env'.")

(defvar-local ptemplate-target-directory nil
  "Target directory of ptemplate expansion.
You can use this in templates. This variable always ends in the
platform-specific directory separator, so you can use this with
`concat' to build file paths.")

(defvar-local ptemplate-source-directory nil
  "Source directory of ptemplate expansion.
Akin to `ptemplate-source-directory'.")
;;; (ptemplate--yasnippet-p :: String -> Bool)
(defun ptemplate--yasnippet-p (file)
  "Check if FILE has a yasnippet extension and nil otherwise."
  (string-suffix-p ".yas" file))

(defvar ptemplate--template-files nil
  "Alist mapping template source files to their targets.
Alist (SRC . TARGET), where SRC and TARGET are strings (see
`ptemplate-map' for details). This variable is always
`let'-bound.")

(defun ptemplate--unix-to-native-path (path)
  "Replace slashes in PATH with the platform's directory separator.
PATH is a file path, as a string, assumed to use slashses as
directory separators. On platform's where that character is
different \(MSDOS, Windows), replace such slashes with the
platform's equivalent."
  (declare (side-effect-free t))
  (if (memq system-type '(msdos windows-nt))
      (replace-regexp-in-string "/" "\\" path nil t)
    path))

(defun ptemplate--dir-find-relative (path)
  "List all files in PATH recursively.
The list is a string of paths beginning with ./ \(or the
platform's equivalent) of all files and directories within it.
Unlike `directory-files-recursively', directories end in the
platform's directory separator. \".\" and \"..\" are not
included."
  (setq path (file-name-as-directory path))
  (cl-loop for file in (let ((default-directory path))
                         (directory-files-recursively "." "" t))
           collect (if (file-directory-p (concat path file))
                       (file-name-as-directory file) file)))

(defun ptemplate--auto-map-file (file)
  "Map FILE to its target, removing special extensions.
See `ptemplate--template-files'."
  (if (member (file-name-extension file) '("keep" "yas"))
      (file-name-sans-extension file)
    file))

(defun ptemplate--list-template-dir-files (path)
  "`ptemplate--list-template-files', but include .ptemplate.el.
PATH specifies the path to examine."
  (cl-loop for file in (ptemplate--dir-find-relative path)
           unless (string-suffix-p ".nocopy" file)
           collect (cons file (ptemplate--auto-map-file file))))

(defun ptemplate--list-template-files (path)
  "Find all files in ptemplate PATH.
Associates each file with its target \(alist (SRC . TARGET)),
removing the extension of special files \(e.g. .nocopy, .yas).
Directories are included. .ptemplate.el and .ptemplate.elc are
removed."
  (cl-delete-if
   (lambda (f)
     (string-match-p
      (ptemplate--unix-to-native-path "\\`\\./\\.ptemplate\\.elc?") (car f)))
   (ptemplate--list-template-dir-files path)))

;;;###autoload
(defun ptemplate-expand-template (source target)
  "Expand the template in SOURCE to TARGET.
If called interactively, SOURCE is prompted using
`ptemplate-template-prompt-function'. TARGET is prompted using
`read-file-name', with the initial directory looked up in
`ptemplate-workspace-alist' using SOURCE's type, defaulting to
`ptemplate-default-workspace'. If even that is nil, use
`default-directory'."
  (interactive (let ((template (funcall ptemplate-template-prompt-function)))
                 (list template (ptemplate--prompt-target template))))
  (when (file-directory-p target)
    ;; NOTE: the error message should mention the user-supplied target (not
    ;; necessarily with a slash at the end), so do this buffer
    ;; (file-name-as-directory).
    (user-error "Directory %s already exists" target))
  ;; empty templates should still create a directory.
  (make-directory target t)

  (setq target (file-name-as-directory target))
  (setq source (file-name-as-directory source))

  (let ((dotptemplate (concat source ".ptemplate.el"))
        (ptemplate--before-snippet-hook)
        (ptemplate--after-copy-hook)
        (ptemplate--finalize-hook)
        (ptemplate--snippet-env)

        ;; the dotptemplate file should know about source and target.
        (ptemplate-source-directory source)
        (ptemplate-target-directory target)

        ;; all template files should start with a ., which makes them source and
        ;; target agnostic. `concat' source/target + file will yield a correct
        ;; path because of this. NOTE: we mustn't override `default-directory'
        ;; for .ptemplate.el, as it should have access to the entire context of
        ;; the current buffer.
        (ptemplate--template-files (ptemplate--list-template-files source)))
    ;;; load .ptemplate.el
    (when (file-exists-p dotptemplate)
      ;; NOTE: arbitrary code execution
      (load-file dotptemplate))

    (cl-loop for (src . targetf) in ptemplate--template-files
             for realsrc = (concat source src)
             ;; all files in `ptemplate--list-template-files' shall end in a
             ;; slash.
             for dir? = (directory-name-p realsrc)

             do
             (make-directory
              ;; directories need to be created "as-is" (they may potentially
              ;; be empty); files must not be created as directories however
              ;; but their containing directories instead. This avoids
              ;; prompts asking the user if they really want to save a file
              ;; even though its containing directory was not made yet.
              (if dir? (concat target src)
                (concat target (file-name-directory src)))
              t)

             unless dir?
             if (ptemplate--yasnippet-p src)
             collect (cons realsrc (concat target targetf)) into yasnippets
             ;;; copy files
             else do (copy-file realsrc (concat target targetf))

             finally do
             (run-hooks 'ptemplate--before-snippet-hook)
             (when yasnippets
               (ptemplate--snippet-chain-start
                yasnippets
                (nconc `((ptemplate-source-directory . ,ptemplate-source-directory)
                         (ptemplate-target-directory . ,ptemplate-target-directory))
                       ptemplate--snippet-env)
                ptemplate--finalize-hook)))))

;;; auxiliary functions for .ptemplate.el API
(defun ptemplate--make-basename-regex (file)
  "Return a regex matching FILE as a basename.
FILE shall be a regular expressions matching a path, separated
using slashes, which will be converted to the platform-specific
directory separator. The returned regex will match if FILE
matches at the start of some string or if FILE matches after a
platform-specific directory separator. The returned regexes can
be used to remove files with certain filenames from directory
listings.

Note that . or .. path components are not handled at all, meaning
that \(string-match-p \(ptemplate--make-basename-regex \"tmp/foo\")
\"tmp/foo/../foo\") will yield nil."
  (declare (side-effect-free t))
  (concat (ptemplate--unix-to-native-path "\\(?:/\\|\\`\\)")
          (ptemplate--unix-to-native-path file) "\\'"))

(defun ptemplate--make-path-regex (path)
  "Make a regex matching PATH if some PATH is below it.
The resulting regex shall match if some other path starts with
PATH. Slashes should be used to separate directories in PATH, the
necessary conversion being done for windows and msdos. The same
caveats apply as for `ptemplate--make-basename-regex'."
  (declare (side-effect-free t))
  (concat "\\`" (regexp-quote (ptemplate--unix-to-native-path path))
          (ptemplate--unix-to-native-path "\\(?:/\\|\\'\\)")))

(defun ptemplate--simplify-user-path (path)
  "Make PATH a template-relative path without any prefix.
PATH's slashes are converted to the native directory separator
and prefixes like ./ and / are removed. Note that directory
separator conversion is not performed."
  (declare (side-effect-free t))
  (let* ((paths (split-string path "/"))
         (paths (cl-delete-if #'string-empty-p paths))
         (paths (cl-delete-if (apply-partially #'string= ".") paths)))
    (string-join paths "/")))

(defun ptemplate--normalize-user-path (path)
  "Make PATH usable to query template files.
PATH shall be a user-supplied template source/target relative
PATH, which will be normalized and whose directory separators
will be converted to the platform's native ones."
  (declare (side-effect-free t))
  (ptemplate--unix-to-native-path
   (concat "./" (ptemplate--simplify-user-path path))))

(defun ptemplate--make-ignore-regex (regexes)
  "Make delete-regex for `ptemplate-ignore'.
REGEXES is a list of strings as described there."
  (declare (side-effect-free t))
  (string-join
   (cl-loop for regex in regexes collect
            (if (string-prefix-p "/" regex)
                (ptemplate--make-path-regex
                 (concat "." (string-remove-suffix "/" regex)))
              (ptemplate--make-basename-regex regex)))
   "\\|"))

(defun ptemplate--prune-template-files (regex)
  "Remove all template whose source files match REGEX.
This function is only supposed to be called from `ptemplate!'."
  (setq ptemplate--template-files
        (cl-delete-if
         (lambda (src-targetf) (string-match-p regex (car src-targetf)))
         ptemplate--template-files)))

(defun ptemplate--prune-duplicate-files (files dup-cb)
  "Find and remove duplicates in FILES.
FILES shall be a list of template file mappings \(see
`ptemplate--template-files'). If a duplicate is encountered, call
DUP-CB using `funcall' and pass to it the (SRC . TARGET) cons
that was encountered later.

Return a new list of mappings with all duplicates removed.

This function uses a hashmap and is as such efficient for large
lists, but doesn't use constant memory."
  ;; hashmap of all target files mapped to `t'
  (cl-loop with known-targets = (make-hash-table :test 'equal)
           for file in files for target = (cdr file)
           ;; already encountered? call DUP-CB
           if (gethash target known-targets) do (funcall dup-cb file)
           ;; remember it as encountered and collect it, since it was first
           else do (puthash target t known-targets) and collect file))

(defun ptemplate--override-files (base-files override)
  "Override all mappings in BASE-FILES with those in OVERRIDE.
Both of them shall be mappings like `ptemplate--template-files'.
BASE-FILES and OVERRIDE may be altered destructively.

Return the new mapping alist, with files from OVERRIDE having
taken precedence.

Note that because duplicate mappings might silently be deleted,
you should call `ptemplate--prune-duplicate-files' with a warning
callback first, to report such duplicates to the user."
  (ptemplate--prune-duplicate-files
   (nconc override base-files)
   ;; duplicates are normal (mappings from OVERRIDE).
   #'ignore))

;;; .ptemplate.el api
(defun ptemplate-map (src target)
  "Map SRC to TARGET for expansion.
SRC is a path relative to the ptemplate being expanded and
TARGET is a path relative to the expansion target."
  (add-to-list 'ptemplate--template-files
               (cons (ptemplate--normalize-user-path src)
                     (ptemplate--normalize-user-path target))))

(defun ptemplate-remap (src target)
  "Remap template file SRC to TARGET.
SRC shall be a template-relative path separated by slashes
\(conversion is done for windows). Using .. in SRC will not work.
TARGET shall be the destination, relative to the expansion
target. See `ptemplate--normalize-user-path' for SRC name rules.

Note that directories are not recursively remapped, which means
that all files contained within them retain their original
\(implicit?) mapping. This means that nonempty directories whose
files haven't been remapped will still be created.

See also `ptemplate-remap-rec'."
  (ptemplate--prune-template-files
   (ptemplate--unix-to-native-path
    (format "\\`%s/?\\'" (ptemplate--normalize-user-path src))))
  (ptemplate-map src target))

(defun ptemplate-remap-rec (src target)
  "Like `ptemplate-remap', but handle directories recursively instead.
For each directory that is mapped to a directory within SRC,
remap it to that same directory relative to TARGET."
  (let ((remap-regex (ptemplate--make-path-regex
                      (ptemplate--normalize-user-path src)))
        (target (ptemplate--normalize-user-path target)))
    (dolist (file ptemplate--template-files)
      (when (string-match-p remap-regex (car file))
        (setcdr file (replace-regexp-in-string
                      remap-regex target file nil t))))))

(defun ptemplate-copy-target (src target)
  "Copy SRC to TARGET, both relative to the expansion target.
Useful if a single template expansion needs to be mapped to two
files, in the :finalize block of `ptemplate!'."
  (copy-file (concat ptemplate-target-directory src)
             (concat ptemplate-target-directory target)))

(defun ptemplate-ignore (&rest regexes)
  "REGEXES specify template files to ignore.
See `ptemplate--make-basename-regex' for details. As a special
case, if a REGEX starts with /, it is interpreted as a template
path to ignore \(see `ptemplate--make-path-regex')."
  (ptemplate--prune-template-files
   (ptemplate--make-ignore-regex regexes)))

(defun ptemplate-include (&rest dirs)
  "Use all files in DIRS for expansion.
The files are added as if they were part of the current template
being expanded, except that .ptemplate.el and .ptemplate.elc are
valid filenames and are not interpreted.

The files defined in the template take precedence. To get the
other behaviour, use `ptemplate-include-override' instead."
  (ptemplate--override-files (mapcan #'ptemplate--list-template-dir-files dirs)
                             ptemplate--template-files))

(defun ptemplate-include-override (&rest dirs)
  "Like `ptemplate-include', but files in DIRS override."
  (ptemplate--override-files
   ptemplate--template-files
   (mapcan #'ptemplate--list-template-dir-files dirs)))

(defun ptemplate-source (dir)
  "Return DIR as if relative to `ptemplate-source-directory'."
  (concat ptemplate-source-directory dir))

(defun ptemplate-target (dir)
  "Return DIR as if relative to `ptemplate-target-directory'."
  (concat ptemplate-target-directory dir))

;; NOTE: ;;;###autoload is unnecessary here, as ptemplate! is only useful in
;; .ptemplate.el files, which are only ever loaded from
;; `ptemplate-expand-template', at which point `ptemplate' is already loaded.
(defmacro ptemplate! (&rest args)
  "Define a smart ptemplate with elisp.
For use in .ptemplate.el files. ARGS is a plist-like list with
any number of sections, specfied as :<section name> FORM... (like
in `use-package'). Sections can appear multiple times: you could,
for example, have multiple :init sections, the FORMs of which
would get evaluated in sequence. Supported keyword are:

:init FORMs to run before expansion. This is the default when no
      section is specified.

:before-snippets FORMs to run before expanding yasnippets.

:after-copy FORMs to run after all files have been copied. The
            ptemplate's snippets need not have been expanded
            already.

:finalize FORMs to run after expansion finishes.

:snippet-env variables to make available in snippets. Their
             values are examined at the end of `ptemplate!' and
             stored. Each element after :env shall be a symbol or
             a list of the form (SYMBOL VALUEFORM), like in
             `let'. The SYMBOLs should not be quoted. If only a
             symbol is specified, its value is taken from the
             current environment. This way, variables can be
             let-bound outside of `ptemplate!' and used in
             snippets.

:ignore See `ptemplate-ignore'. Files are pruned before
        :init.

:subdir Make some template-relative paths appear to be in the
        root. Practically, this means not adding its files and
        including it. Evaluated before :init.

Note that because .ptemplate.el files execute arbitrary code, you
could write them entirely without using this macro (e.g. by
modifying hooks directly, ...). However, you should still use
`ptemplate!', as this makes templates more future-proof and
readable."
  (let ((cur-keyword :init)
        (init-forms)
        (before-yas-eval)
        (after-copy-eval)
        (finalize-eval)
        (snippet-env)
        (ignore-regexes)
        (include-dirs))
    (dolist (arg args)
      (if (keywordp arg)
          (setq cur-keyword arg)
        (pcase cur-keyword
          (:init (push arg init-forms))
          (:before-snippets (push arg before-yas-eval))
          (:after-copy (push arg after-copy-eval))
          (:finalize (push arg finalize-eval))
          (:snippet-env (push arg snippet-env))
          (:ignore (push arg ignore-regexes))
          (:subdir (let ((simplified-path (ptemplate--simplify-user-path arg)))
                     (push (concat (ptemplate--unix-to-native-path "/")
                                   simplified-path)
                           ignore-regexes)
                     (push simplified-path include-dirs))))))
    (macroexp-progn
     (nconc
      (when ignore-regexes
        `((ptemplate--prune-template-files
           ,(ptemplate--make-ignore-regex ignore-regexes))))
      (when include-dirs
        ;; include dirs specified first take precedence
        `((ptemplate-include
           ,@(cl-loop for dir in (nreverse include-dirs)
                      collect (list #'ptemplate-source dir)))))
      (nreverse init-forms)
      (when before-yas-eval
        `((add-hook 'ptemplate--before-snippet-hook
                    (lambda () "Run before expanding snippets."
                      ,@(nreverse before-yas-eval)))))
      (when after-copy-eval
        `((add-hook 'ptemplate--after-copy-hook
                    (lambda () "Run after copying files."
                      ,@(nreverse after-copy-eval)))))
      (when finalize-eval
        `((add-hook 'ptemplate--finalize-hook
                    (lambda () "Run after template expansion finishes."
                      ,@(nreverse finalize-eval)))))
      (when snippet-env
        `((setq
           ptemplate--snippet-env
           (nconc
            ptemplate--snippet-env
            (list ,@(cl-loop
                     for var in snippet-env collect
                     (if (listp var)
                         (list #'cons (macroexp-quote (car var)) (cadr var))
                       `(cons ',var ,var))))))))))))

(provide 'ptemplate)
;;; ptemplate.el ends here
