;;; chezmoi.el --- summary -*- lexical-binding: t -*-

;; Author: Harrison Pielke-Lombardo
;; Maintainer: Harrison Pielke-Lombardo
;; Version: 1.0.0
;; Package-Requires: ((emacs "26.1") magit)
;; Homepage: http://www.github.com/tuh8888/chezmoi.el
;; Keywords: vc


;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.


;;; Commentary:

;; commentary

;;; Code:

(require 'magit)
(require 'cl-lib)

(defvar chezmoi|buffer-target-file)

(defun chezmoi|select-file (files prompt f)
  (funcall f (completing-read prompt files)))

(defun chezmoi|source-file (target-file)
  (let* ((cmd (concat "chezmoi source-path " (when target-file (shell-quote-argument target-file))))
         (result (shell-command-to-string cmd))
         (files (split-string result "\n")))
    (cl-first files)))

(defun chezmoi|managed ()
  (let* ((cmd "chezmoi managed")
         (result (shell-command-to-string cmd))
         (files (split-string result "\n")))
    (cl-map 'list (lambda (file) (concat "~/" file)) files)))

(defun chezmoi|managed-files ()
  (cl-remove-if #'file-directory-p (chezmoi|managed)))

(defun chezmoi|write (target-file)
  "Run =chezmoi apply= on the target file associated with the buffer, overwriting the target with the source state."
  (interactive (list chezmoi|buffer-target-file))
  (if (= 0 (shell-command (concat "chezmoi apply " target-file)))
      (message "Wrote %s" target-file)
    (message "Failed to write file")))

(defun chezmoi|diff (arg)
  "View output of =chezmoi diff= in a diff-buffer."
  (interactive "i")
  (let ((b (get-buffer-create "*chezmoi-diff*")))
    (with-current-buffer b
      (erase-buffer)
      (shell-command "chezmoi diff" b))
    (unless arg
      (switch-to-buffer b)
      (diff-mode)
      (whitespace-mode 0))
    b))

(defun chezmoi|changed-files ()
  "Use chezmoi diff to return the files that have changed"
  (let ((line-beg nil))
    (with-current-buffer (chezmoi|diff t)
      (goto-char (point-max))
      (let ((files nil))
        (while (setq line-beg (re-search-backward "^\\+\\{3\\} .*" nil t))
          (let ((file-name (substring
                            (buffer-substring-no-properties line-beg
                                                            (line-end-position))
                            5)))
            (push (concat "~" file-name) files)))
        files))))

(defun chezmoi|find ()
  "Edit a source file managed by chezmoi. If the target file has the same state
 as the source file,add a hook to save-buffer that applies the source state to
the target state. This way, when the buffer editing the source state is saved
the target state is kept in sync. Note: Does not run =chezmoi edit="
  (interactive)
  (chezmoi|select-file (chezmoi|managed-files)
                       "Select a dotfile to edit: "
                       (lambda (file)
                         (find-file (chezmoi|source-file file))
                         (let ((mode (assoc-default
                                      (file-name-nondirectory file)
                                      auto-mode-alist
                                      'string-match)))
                           (when mode (funcall mode)))
                         (message file)
                         (unless (member file (chezmoi|changed-files))
                           (add-hook 'after-save-hook
                                     (lambda () (chezmoi|write file)) 0 t))
                         (setq-local chezmoi|buffer-target-file file))))

(defun chezmoi|ediff ()
  "Choose a dotfile to merge with its source using ediff.
Note: Does not run =chezmoi merge=."
  (interactive)
  (chezmoi|select-file (chezmoi|changed-files)
                       "Select a dotfile to merge: "
                       (lambda (file)
                         (ediff-files (chezmoi|source-file file) file))))

(defun chezmoi|magit-status ()
  "Show the status of the chezmoi source repository."
  (interactive)
  (magit-status-setup-buffer (chezmoi|source-file nil)))

(defun chezmoi|select-files (files prompt f)
  "Iteratively select file from files and apply f to each selected. Selected
files are removed after they are selected."
  (let ((files (copy-list files)))
    (while files
      (chezmoi|select-file files
                           (concat prompt " (C-g to stop): ")
                           (lambda (file)
                             (funcall f file)
                             (setq files (remove file files)))))))

(defun chezmoi|write-from-target (target-file)
  "Apply the source state to the target state. Useful for files which are
autogenerated outside of chezmoi."
  (interactive (list chezmoi|buffer-target-file))
  (with-current-buffer (find-file-noselect (chezmoi|source-file target-file))
    (replace-buffer-contents (find-file-noselect target-file))))

(defun chezmoi|write-files ()
  "Force overwrite multiple dotfiles with their source state."
  (interactive)
  (chezmoi|select-files (chezmoi|changed-files)
                        "Select dotfile to apply source state changes"
                        #'chezmoi|write))


(defun chezmoi|write-files-from-target ()
  "Force overwrite the source state of multiple dotfiles with their target
state."
  (interactive)
  (chezmoi|select-files (chezmoi|changed-files)
                        "Select a dotfile to overwrite its source state with target state"
                        #'chezmoi|write-from-target))

(defun chezmoi|open-target ()
  (interactive)
  (find-file chezmoi|buffer-target-file))

(defun chezmoi|dired-add-marked-files ()
  (interactive)
  (dolist (file (dired-get-marked-files))
    (shell-command (concat "chezmoi add " file))))

(provide 'chezmoi)

;;; chezmoi.el ends here
