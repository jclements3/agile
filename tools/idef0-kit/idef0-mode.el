;;; idef0-mode.el --- Major mode for the pipe-path IDEF0 DSL  -*- lexical-binding: t; -*-

;; Setup:
;;   (add-to-list 'load-path "~/path/to/idef0-kit")
;;   (require 'idef0-mode)
;;   ;; and put the idef0-kit directory on your shell PATH, or:
;;   (setq idef0-program "~/path/to/idef0-kit/idef0")
;;
;; Files ending in .idef0, and .txt files whose first line contains
;; "-*- mode: idef0 -*-", open in idef0-mode.
;;
;; Keys:
;;   C-c C-c   lint this file            C-c C-p   lint whole project (dir)
;;   C-c C-v   view plates (project)     C-c C-d   dump numbered tree
;;   C-c C-l   interface table           C-c C-n   fmt: freeze numbers in buffer
;;   C-c C-u   fmt: strip back to #      C-c C-f   jump to link target
;;   M-RET     insert sibling line       M-up/down move line or subtree
;;   TAB       fold subtree (on t/a) or indent
;;
;; A project is all *.txt and *.idef0 files in this file's directory.

(require 'outline)
(require 'cl-lib)

(defgroup idef0 nil "IDEF0 DSL editing." :group 'languages)

(defcustom idef0-program "idef0"
  "Path to the idef0 tool (multi-command core script)."
  :type 'string :group 'idef0)

(defcustom idef0-indent-width 2
  "Spaces per nesting level."
  :type 'integer :group 'idef0)

;; ------------------------------------------------------------ font lock
(defvar idef0-font-lock-keywords
  `((,(rx bol (* space) (or ";;" "##") (* nonl)) . font-lock-doc-face)
    (,(rx (any " \t") (group "##" (* nonl)) eol) (1 font-lock-doc-face t))
    (,(rx bol (* space) (any ";#") (* nonl)) . font-lock-comment-face)
    (,(rx (any " \t") (group "#" (not (any "#")) (* nonl)) eol)
     (1 font-lock-comment-face t))
    (,(rx bol (* space) (group "t" (or "#" (any "A-Za-z"))) (+ space)
          (group (+ (not (any "<>|\n")))))
     (1 font-lock-keyword-face) (2 font-lock-function-name-face))
    (,(rx bol (* space) (group "a" (or "#" (any "1-9")
                                       (seq (any "A-Za-z") (+ digit) ".")))
          (+ space) (group (+ (not (any "<>|\n")))))
     (1 font-lock-keyword-face) (2 font-lock-variable-name-face))
    (,(rx bol (* space) (group (any "i") (or "#" (any "1-9"))) (+ space))
     (1 font-lock-type-face))
    (,(rx bol (* space) (group (any "c") (or "#" (any "1-9"))) (+ space))
     (1 font-lock-constant-face))
    (,(rx bol (* space) (group (any "o") (or "#" (any "1-9"))) (+ space))
     (1 font-lock-builtin-face))
    (,(rx bol (* space) (group (any "m") (or "#" (any "1-9"))) (+ space))
     (1 font-lock-preprocessor-face))
    (,(rx (group (any "<>")) (+ space) (group (+ nonl)))
     (1 font-lock-warning-face) (2 font-lock-string-face))))

;; ------------------------------------------------------------ commands
(defun idef0--project-files ()
  (directory-files default-directory t "\\.\\(txt\\|idef0\\)\\'"))

(defun idef0--run (cmd files)
  (compile (mapconcat #'shell-quote-argument
                      (append (list idef0-program cmd) files) " ")))

(defun idef0-lint ()
  "Lint the current file."
  (interactive)
  (save-buffer)
  (idef0--run "lint" (list buffer-file-name)))

(defun idef0-lint-project ()
  "Lint every model file in this directory."
  (interactive)
  (save-buffer)
  (idef0--run "lint" (idef0--project-files)))

(defun idef0-dump ()
  "Show the numbered tree for the project."
  (interactive)
  (save-buffer)
  (idef0--run "dump" (idef0--project-files)))

(defun idef0-links ()
  "Show the project interface table."
  (interactive)
  (save-buffer)
  (idef0--run "links" (idef0--project-files)))

(defun idef0-view-plates ()
  "Render the project's plates to text and page through them."
  (interactive)
  (save-buffer)
  (let ((buf (get-buffer-create "*idef0 plates*")))
    (with-current-buffer buf (erase-buffer))
    (apply #'call-process idef0-program nil buf nil
           "text" (idef0--project-files))
    (with-current-buffer buf (goto-char (point-min)) (view-mode 1))
    (pop-to-buffer buf)))

(defun idef0--fmt (mode)
  (save-buffer)
  (let ((exit (call-process idef0-program nil nil nil
                            "fmt" mode "--write" buffer-file-name)))
    (if (zerop exit)
        (progn (revert-buffer t t t) (message "idef0 fmt %s: done" mode))
      (idef0--run "lint" (list buffer-file-name)))))

(defun idef0-fmt-number ()
  "Freeze derived numbers into this buffer's tag suffixes."
  (interactive) (idef0--fmt "--number"))

(defun idef0-fmt-auto ()
  "Strip tag suffixes back to # (t keeps its letter)."
  (interactive) (idef0--fmt "--auto"))

(defun idef0-follow-link ()
  "Jump to the target of the link on this line (textual search)."
  (interactive)
  (let* ((line (buffer-substring-no-properties
                (line-beginning-position) (line-end-position)))
         (path (and (string-match "[<>][ \t]*\\(.+\\)$" line)
                    (match-string 1 line)))
         (segs (and path (split-string path "|" t "[ \t]+")))
         (flow (car (last segs))))
    (unless segs (user-error "No link on this line"))
    (let ((hit nil))
      (dolist (f (idef0--project-files))
        (unless hit
          (with-current-buffer (find-file-noselect f)
            (save-excursion
              (goto-char (point-min))
              (when (re-search-forward
                     (concat "^[ \t]*[icom]\\(?:#\\|[1-9]\\)[ \t]+"
                             (regexp-quote flow)) nil t)
                (setq hit (cons f (line-number-at-pos))))))))
      (if (not hit) (user-error "Target %s not found" flow)
        (find-file (car hit))
        (goto-char (point-min))
        (forward-line (1- (cdr hit)))))))

(defun idef0-insert-sibling ()
  "Insert a new line below with the same indentation and tag, suffix #."
  (interactive)
  (let* ((line (buffer-substring-no-properties
                (line-beginning-position) (line-end-position)))
         (tag (if (string-match "^\\([ \t]*\\)\\([taicom]\\)" line)
                  (concat (match-string 1 line) (match-string 2 line) "# ")
                "a# ")))
    (end-of-line) (newline) (insert tag)))

(defun idef0-tab ()
  "Fold subtree on activity lines, else indent."
  (interactive)
  (if (save-excursion (beginning-of-line)
                      (looking-at "^[ \t]*[ta]\\(#\\|[A-Za-z]?[0-9]*\\.?\\)[ \t]"))
      (outline-toggle-children)
    (insert (make-string idef0-indent-width ?\s))))

(defun idef0-move-down () (interactive) (idef0--move 1))
(defun idef0-move-up   () (interactive) (idef0--move -1))
(defun idef0--move (dir)
  (if (save-excursion (beginning-of-line)
                      (looking-at "^[ \t]*[ta]"))
      (if (> dir 0) (outline-move-subtree-down) (outline-move-subtree-up))
    (let ((col (current-column)))
      (beginning-of-line)
      (let ((line (delete-and-extract-region
                   (point) (min (1+ (line-end-position)) (point-max)))))
        (forward-line dir) (insert line) (forward-line -1)
        (move-to-column col)))))

(defun idef0--outline-level ()
  (save-excursion
    (beginning-of-line)
    (looking-at "^\\([ \t]*\\)")
    (1+ (/ (- (match-end 1) (match-beginning 1)) idef0-indent-width))))

;; ---------------------------------------------------------------- mode
(defvar idef0-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'idef0-lint)
    (define-key map (kbd "C-c C-p") #'idef0-lint-project)
    (define-key map (kbd "C-c C-v") #'idef0-view-plates)
    (define-key map (kbd "C-c C-d") #'idef0-dump)
    (define-key map (kbd "C-c C-l") #'idef0-links)
    (define-key map (kbd "C-c C-n") #'idef0-fmt-number)
    (define-key map (kbd "C-c C-u") #'idef0-fmt-auto)
    (define-key map (kbd "C-c C-f") #'idef0-follow-link)
    (define-key map (kbd "M-RET")   #'idef0-insert-sibling)
    (define-key map (kbd "M-<down>") #'idef0-move-down)
    (define-key map (kbd "M-<up>")   #'idef0-move-up)
    (define-key map (kbd "TAB")     #'idef0-tab)
    (define-key map (kbd "<backtab>") #'outline-show-all)
    map))

;;;###autoload
(define-derived-mode idef0-mode text-mode "IDEF0"
  "Major mode for the pipe-path IDEF0 DSL."
  (setq-local font-lock-defaults '(idef0-font-lock-keywords))
  (setq-local outline-regexp "^[ \t]*[ta]\\(#\\|[A-Za-z]?[0-9]*\\.?\\)[ \t]")
  (setq-local outline-level #'idef0--outline-level)
  (outline-minor-mode 1)
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width idef0-indent-width)
  (setq-local comment-start "# ")
  (setq-local comment-start-skip "[;#]+[ \t]*")
  (setq-local imenu-generic-expression
              '(("Activities"
                 "^[ \t]*[ta]\\(?:#\\|[A-Za-z]?[0-9]*\\.?\\)[ \t]+\\([^<>|\n]+\\)" 1))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.idef0\\'" . idef0-mode))

(provide 'idef0-mode)
;;; idef0-mode.el ends here

;; Fontify ```idef0 fences natively inside markdown-mode buffers.
(with-eval-after-load 'markdown-mode
  (add-to-list 'markdown-code-lang-modes '("idef0" . idef0-mode)))
