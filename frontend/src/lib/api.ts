const API_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:8000'

export interface Todo {
  id: number
  title: string
  description: string | null
  completed: boolean
  created_at: string
  updated_at: string
}

export interface TodoCreateInput {
  title: string
  description?: string | null
}

export interface TodoUpdateInput {
  title?: string
  description?: string | null
  completed?: boolean
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
  if (!res.ok) {
    throw new Error(`Request to ${path} failed with ${res.status}`)
  }
  if (res.status === 204) {
    return undefined as T
  }
  return res.json() as Promise<T>
}

export const api = {
  listTodos: () => request<Array<Todo>>('/todos'),
  createTodo: (input: TodoCreateInput) =>
    request<Todo>('/todos', { method: 'POST', body: JSON.stringify(input) }),
  updateTodo: (id: number, input: TodoUpdateInput) =>
    request<Todo>(`/todos/${id}`, { method: 'PUT', body: JSON.stringify(input) }),
  deleteTodo: (id: number) => request<void>(`/todos/${id}`, { method: 'DELETE' }),
}
