import { createFileRoute } from '@tanstack/react-router'
import { useEffect, useState } from 'react'

import type { Todo } from '#/lib/api'
import { api } from '#/lib/api'

export const Route = createFileRoute('/')({ component: TodoPage })

function TodoPage() {
  const [todos, setTodos] = useState<Array<Todo>>([])
  const [title, setTitle] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    refresh()
  }, [])

  async function refresh() {
    try {
      setLoading(true)
      setTodos(await api.listTodos())
      setError(null)
    } catch {
      setError('Could not reach the API. Is the backend running?')
    } finally {
      setLoading(false)
    }
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim()) return
    await api.createTodo({ title: title.trim() })
    setTitle('')
    await refresh()
  }

  async function handleToggle(todo: Todo) {
    await api.updateTodo(todo.id, { completed: !todo.completed })
    await refresh()
  }

  async function handleDelete(todo: Todo) {
    await api.deleteTodo(todo.id)
    await refresh()
  }

  return (
    <div className="mx-auto max-w-xl p-8">
      <h1 className="text-3xl font-bold">Todo</h1>

      <form onSubmit={handleCreate} className="mt-6 flex gap-2">
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="What needs doing?"
          className="flex-1 rounded border border-gray-300 px-3 py-2"
        />
        <button
          type="submit"
          className="rounded bg-blue-600 px-4 py-2 text-white hover:bg-blue-700"
        >
          Add
        </button>
      </form>

      {error && <p className="mt-4 text-red-600">{error}</p>}
      {loading && <p className="mt-4 text-gray-500">Loading...</p>}

      <ul className="mt-6 space-y-2">
        {todos.map((todo) => (
          <li
            key={todo.id}
            className="flex items-center justify-between rounded border border-gray-200 px-3 py-2"
          >
            <label className="flex flex-1 items-center gap-3">
              <input
                type="checkbox"
                checked={todo.completed}
                onChange={() => handleToggle(todo)}
              />
              <span className={todo.completed ? 'text-gray-400 line-through' : ''}>
                {todo.title}
              </span>
            </label>
            <button
              onClick={() => handleDelete(todo)}
              className="text-sm text-red-500 hover:text-red-700"
            >
              Delete
            </button>
          </li>
        ))}
        {!loading && todos.length === 0 && (
          <p className="text-gray-500">No todos yet — add one above.</p>
        )}
      </ul>
    </div>
  )
}
